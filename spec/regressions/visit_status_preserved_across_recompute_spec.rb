# frozen_string_literal: true

require 'rails_helper'

# Originally covered Areas::Visits::Create and Places::Visits::Create
# (retired 2026-05-27). The contract — "user-modified visit status / name
# survives a re-run of visit detection" — is now provided by SmartDetect's
# upstream Point.where(visit_id: nil) scope (points already in a visit are
# never re-clustered) AND Creator#find_existing_visit's ±1h / 100m dedup.
RSpec.describe 'Visit status is preserved across SmartDetect re-runs' do
  let!(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }
  let(:lock_key) { "tracks:per_user_lock:#{user.id}" }

  before do
    Sidekiq.redis { |r| r.del(lock_key) }
    # 6 stationary points: enough to clear visit_min_points (default 3) and
    # visit_min_duration_minutes (default 5 min). Spaced 60 s apart so DBSCAN
    # density-fill stays out of it.
    6.times do |i|
      create(:point, user: user,
                     latitude: 0, longitude: 0, lonlat: 'POINT(0 0)',
                     timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
    end
  end

  after { Sidekiq.redis { |r| r.del(lock_key) } }

  def run_smart_detect
    Visits::SmartDetect.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call
  end

  it 'keeps a confirmed visit confirmed and does not create a duplicate when re-run' do
    visits = run_smart_detect
    expect(visits.size).to eq(1)
    visit = visits.first
    visit.update!(status: :confirmed)

    expect { run_smart_detect }.not_to change { user.visits.count }
    expect(visit.reload.status).to eq('confirmed')
  end

  it 'keeps a declined visit declined when re-run' do
    visits = run_smart_detect
    visit = visits.first
    visit.update!(status: :declined)

    run_smart_detect

    expect(visit.reload.status).to eq('declined')
  end

  it 'keeps a user-chosen visit name when re-run' do
    visits = run_smart_detect
    visit = visits.first
    visit.update!(status: :confirmed, name: 'Home sweet home')

    run_smart_detect

    expect(visit.reload.name).to eq('Home sweet home')
  end

  it 'still creates new visits with status suggested on first detection' do
    visits = run_smart_detect

    expect(visits.first.status).to eq('suggested')
  end
end
