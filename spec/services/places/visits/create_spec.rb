# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::Visits::Create do
  let(:user) { create(:user) }
  let!(:place) { create(:place, user: user, latitude: 54.2905245, longitude: 13.0948638) }
  let(:base_ts) { Time.utc(2024, 5, 1, 12, 0, 0).to_i }

  def run
    described_class.new(user, user.reload.places, throttle_seconds: 0).call
  end

  # A point a few metres from the place (unique lonlat per call to satisfy the
  # uniqueness validation), at the given timestamp.
  def near_point(timestamp, seq:, **attrs)
    lon = 13.0948638 + (seq * 0.00001)
    lat = 54.2905245 + (seq * 0.00001)
    create(:point, user: user, latitude: lat, longitude: lon,
                   lonlat: "POINT(#{lon} #{lat})", timestamp: timestamp, **attrs)
  end

  # Count the per-month point-loading queries (`place_points_for_month`),
  # identified by their `ORDER BY "points"."timestamp"` clause — the distinct
  # months query orders by month, not by points.
  def count_point_load_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      sql = args.last[:sql].to_s.downcase
      count += 1 if sql.include?('order by "points"."timestamp"')
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it 'creates a suggested visit for unvisited points near the place' do
    near_point(base_ts, seq: 1)
    near_point(base_ts + 5.minutes, seq: 2)
    near_point(base_ts + 10.minutes, seq: 3)

    expect { run }.to change(Visit, :count).by(1)

    visit = Visit.last
    expect(visit.place_id).to eq(place.id)
    expect(visit.status).to eq('suggested')
    expect(Point.where(user_id: user.id).where.not(visit_id: nil).count).to eq(3)
  end

  it 'is idempotent — a second run creates no duplicate visit' do
    near_point(base_ts, seq: 1)
    near_point(base_ts + 5.minutes, seq: 2)
    near_point(base_ts + 10.minutes, seq: 3)
    run

    expect { run }.not_to change(Visit, :count)
  end

  it 'does not reload month points for a place whose nearby points are all already visited' do
    near_point(base_ts, seq: 1)
    near_point(base_ts + 5.minutes, seq: 2)
    near_point(base_ts + 10.minutes, seq: 3)
    run # first run assigns visit_id to every nearby point

    queries = count_point_load_queries { run }

    expect(queries).to eq(0)
  end

  it 'pauses between places when a throttle is configured' do
    near_point(base_ts, seq: 1)
    near_point(base_ts + 5.minutes, seq: 2)
    near_point(base_ts + 10.minutes, seq: 3)

    service = described_class.new(user, user.reload.places, throttle_seconds: 0.01)
    allow(service).to receive(:sleep)

    service.call

    expect(service).to have_received(:sleep).with(0.01).at_least(:once)
  end

  it 'does not pause when the throttle is zero' do
    near_point(base_ts, seq: 1)

    service = described_class.new(user, user.reload.places, throttle_seconds: 0)
    allow(service).to receive(:sleep)

    service.call

    expect(service).not_to have_received(:sleep)
  end

  it 'extends an existing visit when a new adjacent point arrives' do
    near_point(base_ts, seq: 1)
    near_point(base_ts + 5.minutes, seq: 2)
    near_point(base_ts + 10.minutes, seq: 3)
    run
    original_visit_id = Point.where(user_id: user.id).pluck(:visit_id).compact.first
    expect(original_visit_id).to be_present

    new_point = near_point(base_ts + 15.minutes, seq: 4)
    run

    expect(Visit.count).to eq(1)
    expect(new_point.reload.visit_id).to eq(original_visit_id)
  end
end
