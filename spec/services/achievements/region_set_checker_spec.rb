# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::RegionSetChecker do
  let(:user) { create(:user) }
  let(:definition) do
    Achievements::Definition.new(
      key: 'explorer_test', kind: 'region_set', name: 'Test Explorer',
      country: 'TT', regions: { 'TT-01' => 'Testland' }
    )
  end
  let!(:region) { create(:region, code: 'TT-01', geom: 'MULTIPOLYGON (((0 0, 0 1, 1 1, 1 0, 0 0)))') }
  let(:base_ts) { DateTime.new(2026, 1, 1).to_i }

  before { allow(Achievements::Registry).to receive(:region_sets).and_return([definition]) }

  def create_dwell_points(count:, step: 600)
    count.times { |i| create(:point, user:, longitude: 0.5, latitude: 0.5, timestamp: base_ts + (i * step)) }
  end

  def run_checker(notify: true)
    described_class.new(user, notify: notify).call
  end

  describe '#call' do
    context 'when dwell crosses the threshold' do
      before { create_dwell_points(count: 8) }

      it 'marks the region earned in state' do
        run_checker

        progress = user.achievement_progresses.find_by!(achievement_key: 'explorer_test')
        expect(progress.state['earned']).to have_key('TT-01')
        expect(progress.state['dwell']['TT-01']).to eq(4200)
      end

      it 'creates a region notification and a completion notification' do
        expect { run_checker }.to change(Notification, :count).by(2)
        expect(Notification.pluck(:title)).to include('Testland explored!', 'Test Explorer completed!')
      end

      it 'creates the award once' do
        run_checker

        expect(user.user_achievements.where(achievement_key: 'explorer_test').count).to eq(1)
      end

      it 'is idempotent on re-run' do
        run_checker

        expect { run_checker }.not_to change(Notification, :count)
        expect(user.user_achievements.count).to eq(1)
      end

      it 'suppresses notifications when notify is false' do
        expect { run_checker(notify: false) }.not_to change(Notification, :count)
        expect(user.user_achievements.count).to eq(1)
      end
    end

    context 'when dwell stays below the threshold' do
      before { create_dwell_points(count: 2) }

      it 'accumulates dwell without earning' do
        run_checker

        progress = user.achievement_progresses.find_by!(achievement_key: 'explorer_test')
        expect(progress.state['dwell']['TT-01']).to eq(600)
        expect(progress.state['earned']).to be_blank
        expect(user.user_achievements).to be_empty
      end
    end

    context 'when older points arrive after the cursor advanced' do
      it 'recomputes dwell from scratch without double-counting' do
        create_dwell_points(count: 3)
        run_checker

        3.times { |i| create(:point, user:, longitude: 0.5, latitude: 0.5, timestamp: base_ts - 3600 + (i * 600)) }
        described_class.new(user, oldest_timestamp: base_ts - 3600).call

        progress = user.achievement_progresses.find_by!(achievement_key: 'explorer_test')
        expect(progress.state['dwell']['TT-01']).to eq(4200)
      end

      it 'never revokes an earned region when recomputed dwell falls below the threshold' do
        create_dwell_points(count: 8)
        run_checker
        user.points.order(timestamp: :desc).limit(5).destroy_all

        expect { described_class.new(user, oldest_timestamp: base_ts - 3600).call }
          .not_to change(Notification, :count)

        progress = user.achievement_progresses.find_by!(achievement_key: 'explorer_test')
        expect(progress.state['dwell']['TT-01']).to eq(1200)
        expect(progress.state['earned']).to have_key('TT-01')
        expect(user.user_achievements.where(achievement_key: 'explorer_test').count).to eq(1)
      end
    end
  end
end
