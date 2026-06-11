# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::Visits::Create do
  let(:user)  { create(:user) }
  let(:place) { create(:place, user: user) }

  let(:ts_start) { Time.zone.parse('2024-05-01 10:00:00').to_i }
  let(:ts_end)   { Time.zone.parse('2024-05-01 11:00:00').to_i }

  let(:visit_points) do
    [
      create(:point, user: user, timestamp: ts_start),
      create(:point, user: user, timestamp: ts_end)
    ]
  end

  let(:service) { described_class.new(user, [place]) }

  def run_create
    service.send(:create_or_update_visit, place, '2024-05-01 10:00 - 11:00', visit_points)
  end

  describe '#create_or_update_visit' do
    context 'idempotency — running twice for the same place/start' do
      it 'does not create a duplicate visit on the second run' do
        run_create
        run_create

        expect(Visit.where(place_id: place.id, user_id: user.id).count).to eq(1)
      end

      it 'updates ended_at on the second run instead of creating a second visit' do
        run_create
        second_end_ts = ts_end + 30.minutes.to_i
        late_point    = create(:point, user: user, timestamp: second_end_ts)
        points_second = [visit_points.first, late_point]

        service.send(:create_or_update_visit, place, '2024-05-01 10:00 - 11:30', points_second)

        visits = Visit.where(place_id: place.id, user_id: user.id)
        expect(visits.count).to eq(1)
        expect(visits.first.ended_at).to be_within(1.second).of(Time.zone.at(second_end_ts))
      end
    end

    context 'pre-existing winner — visit already created by a racing job' do
      it 'reuses the pre-created visit and assigns all points to it' do
        started_at = Time.zone.at(ts_start)
        winner = create(:visit,
                        user: user,
                        place: place,
                        started_at: started_at,
                        ended_at: started_at + 30.minutes,
                        duration: 30,
                        name: 'pre-existing',
                        status: :suggested)

        run_create

        expect(Visit.where(place_id: place.id, user_id: user.id).count).to eq(1)
        expect(Visit.find(winner.id).ended_at).to be_within(1.second).of(Time.zone.at(ts_end))
        visit_point_ids = visit_points.map(&:id)
        expect(Point.where(id: visit_point_ids).pluck(:visit_id).uniq).to eq([winner.id])
      end
    end
  end

  describe 'DB constraint — partial unique index' do
    let(:started_at) { Time.zone.at(ts_start) }

    it 'raises RecordNotUnique when two visits share the same user/place/started_at' do
      create(:visit, user: user, place: place, started_at: started_at,
                     ended_at: started_at + 1.hour, duration: 60)
      duplicate = build(:visit, user: user, place: place, started_at: started_at,
                                ended_at: started_at + 1.hour, duration: 60)

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'does NOT raise when place_id is nil with the same user/started_at' do
      create(:visit, user: user, place: place, started_at: started_at,
                     ended_at: started_at + 1.hour, duration: 60)
      area_visit = build(:visit, user: user, place_id: nil, started_at: started_at,
                                 ended_at: started_at + 1.hour, duration: 60)

      expect { area_visit.save! }.not_to raise_error
    end
  end
end
