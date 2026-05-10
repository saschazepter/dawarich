# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }

  def advisory_locks_enabled?
    ActiveRecord::Base.connection_pool.db_config.configuration_hash[:advisory_locks] != false
  end

  describe 'advisory lock' do
    it 'acquires pg_advisory_xact_lock(user.id) when advisory locks are enabled' do
      skip 'advisory_locks disabled in test env' unless advisory_locks_enabled?

      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts, accuracy: 10, visit_id: nil)

      sql_log = []
      original = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        sql_log << sql.to_s
        original.call(sql, *rest)
      end

      described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1).call

      expect(sql_log.any? { |s| s.include?("pg_advisory_xact_lock(#{user.id})") }).to eq(true)
    end
  end

  describe 'happy path' do
    it 'creates visits when DBSCAN finds clusters' do
      5.times do |i|
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
end
