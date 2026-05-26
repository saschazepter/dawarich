# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }

  describe 'per-user lock' do
    let(:lock_key) { "tracks:per_user_lock:#{user.id}" }

    before { Sidekiq.redis { |r| r.del(lock_key) } }
    after { Sidekiq.redis { |r| r.del(lock_key) } }

    it 'acquires Tracks::PerUserLock during the run and releases afterwards' do
      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts, accuracy: 10, visit_id: nil)

      observed_during = nil
      allow_any_instance_of(Visits::DbscanClusterer).to receive(:call) do
        observed_during = Sidekiq.redis { |r| r.exists(lock_key) }
        []
      end

      described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1).call

      expect(observed_during).to eq(1)
      expect(Sidekiq.redis { |r| r.exists(lock_key) }).to eq(0)
    end
  end

  describe 'happy path' do
    it 'creates visits when DBSCAN finds clusters' do
      6.times do |i|
        create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                       timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
      end

      visits = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

      expect(visits.size).to be >= 1
    end
  end

  describe 'failure handling' do
    it 're-raises ActiveRecord::StatementInvalid from the clusterer' do
      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts, accuracy: 10, visit_id: nil)

      allow_any_instance_of(Visits::DbscanClusterer).to receive(:call)
        .and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1).call }
        .to raise_error(ActiveRecord::StatementInvalid, /boom/)
    end
  end

  describe 'logging' do
    it 'emits a single structured INFO log' do
      3.times do |i|
        create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                       timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
      end

      log_pattern = /\[Visits::SmartDetect\] user_id=#{user.id} range=\d+\.\.\d+ batches=\d+ /
      log_pattern_full = /#{log_pattern}points_in=\d+ clusters=\d+ visits_created=\d+ duration_ms=\d+/
      expect(Rails.logger).to receive(:info).with(a_string_matching(log_pattern_full)).at_least(:once)
      allow(Rails.logger).to receive(:info)

      described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call
    end
  end

  describe 'plan window clamping' do
    let(:lite_user) { create(:user, plan: :lite) }

    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'clamps start_at to the data window for plan-restricted users' do
      window_start = lite_user.data_window_start.to_i
      requested_start = window_start - 30.days.to_i

      detector = described_class.new(lite_user, start_at: requested_start, end_at: window_start + 60)

      expect(detector.start_at).to eq(window_start)
    end

    it 'leaves start_at untouched for unrestricted (Pro) users' do
      pro_user = create(:user, plan: :pro)
      requested_start = base_ts - 365.days.to_i

      detector = described_class.new(pro_user, start_at: requested_start, end_at: base_ts)

      expect(detector.start_at).to eq(requested_start)
    end
  end
end
