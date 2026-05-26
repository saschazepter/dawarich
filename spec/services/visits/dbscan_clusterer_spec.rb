# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::DbscanClusterer do
  let(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }

  def make_point(at:, lat:, lon:, accuracy: 10, owner: user)
    create(:point, user: owner, latitude: lat, longitude: lon,
                   lonlat: "POINT(#{lon} #{lat})",
                   timestamp: at, accuracy: accuracy, visit_id: nil)
  end

  describe 'synthetic-point cap' do
    it 'caps generated synthetic points at MAX_SYNTHETIC_PER_GAP per gap' do
      make_point(at: base_ts,        lat: 52.5,      lon: 13.4)
      make_point(at: base_ts + 1800, lat: 52.50001,  lon: 13.40001)
      make_point(at: base_ts + 1830, lat: 52.500011, lon: 13.400011)

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1900).call

      expect(clusters.size).to eq(1)
      expect(clusters.first[:point_count]).to be <= described_class::MAX_SYNTHETIC_PER_GAP + 3
    end
  end

  describe 'connection state' do
    # The previous contract used a bare `SET statement_timeout` outside a transaction
    # and a `RESET` in an ensure block. On PgBouncer transaction-pool (Cloud), a SET
    # outside an explicit transaction binds to one backend; the next statement may
    # land elsewhere with no timeout. Wrap in an explicit transaction with SET LOCAL
    # so the timeout is bound to the same backend as the DBSCAN query.
    it 'wraps the DBSCAN query in an explicit transaction using SET LOCAL statement_timeout' do
      executed_sql = []
      original_execute = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        executed_sql << sql.to_s if sql.to_s.match?(/statement_timeout/i)
        original_execute.call(sql, *rest)
      end

      open_before = ActiveRecord::Base.connection.open_transactions

      nesting_during_query = nil
      original_exec_query = ActiveRecord::Base.connection.method(:exec_query)
      allow(ActiveRecord::Base.connection).to receive(:exec_query) do |*args|
        nesting_during_query = ActiveRecord::Base.connection.open_transactions
        original_exec_query.call(*args)
      end

      described_class.new(user, start_at: 0, end_at: 1).call

      open_after = ActiveRecord::Base.connection.open_transactions

      expect(executed_sql).to include(match(/\ASET\s+LOCAL\s+statement_timeout/i))
      expect(executed_sql).not_to include(match(/RESET\s+statement_timeout/i))
      expect(nesting_during_query).to eq(open_before + 1)
      expect(open_after).to eq(open_before)
    end
  end

  describe 'logging' do
    it 'emits a single structured INFO log on success' do
      ts = 1_700_000_000
      3.times do |i|
        make_point(at: ts + i * 60, lat: 52.5, lon: 13.4)
      end

      header = /\[Visits::DbscanClusterer\] user_id=#{user.id} range=\d+\.\.\d+/
      log_pattern = /#{header} candidate_points=\d+ clusters=\d+ duration_ms=\d+/
      expect(Rails.logger).to receive(:info).with(a_string_matching(log_pattern))

      described_class.new(user, start_at: ts - 1, end_at: ts + 600).call
    end
  end

  describe 'stationarity gate' do
    it 'accepts a clustered stop where the device is not moving' do
      6.times do |i|
        drift = i * 0.00001
        make_point(at: base_ts + i * 60, lat: 52.5 + drift, lon: 13.4 + drift)
      end

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 400).call

      expect(clusters.size).to eq(1)
      expect(clusters.first[:point_count]).to eq(6)
    end

    it 'rejects a drive-by cluster moving along a road faster than walking pace' do
      6.times do |i|
        lat_offset = i * 0.0005
        make_point(at: base_ts + i * 12, lat: 52.5 + lat_offset, lon: 13.4)
      end

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 100).call

      expect(clusters).to be_empty
    end

    it 'rejects a cluster whose real points are dominated by sustained movement' do
      user.update!(settings: (user.settings || {}).merge('visit_min_duration_minutes' => 1))

      6.times do |i|
        lat_offset = i * 0.0005
        make_point(at: base_ts + i * 30, lat: 52.5 + lat_offset, lon: 13.4)
      end

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 200).call

      expect(clusters).to be_empty
    end
  end

  describe 'minimum real points (synthetic fill cannot fabricate a visit)' do
    it 'rejects a cluster where only two real points are surrounded by synthetic fill' do
      make_point(at: base_ts,       lat: 52.5,     lon: 13.4)
      make_point(at: base_ts + 600, lat: 52.50005, lon: 13.40005)

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 700).call

      expect(clusters).to be_empty
    end
  end

  describe 'user-tunable time-gap (same-cluster segmentation)' do
    let(:settings_without_density_fill) do
      { 'visit_density_fill_enabled' => false, 'visit_min_duration_minutes' => 1 }
    end

    it 'splits a stationary cluster into two visits when points cross the gap threshold' do
      user.update!(settings: (user.settings || {}).merge(settings_without_density_fill,
                                                         'time_threshold_minutes' => 10))

      6.times do |i|
        drift = i * 0.00001
        make_point(at: base_ts + i * 30, lat: 52.5 + drift, lon: 13.4 + drift)
      end
      6.times do |i|
        drift = i * 0.00001
        make_point(at: base_ts + 900 + i * 30, lat: 52.5 + drift, lon: 13.4 + drift)
      end

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1200).call

      expect(clusters.size).to eq(2)
    end

    it 'keeps the same cluster as one visit when the gap stays under the threshold' do
      user.update!(settings: (user.settings || {}).merge(settings_without_density_fill,
                                                         'time_threshold_minutes' => 30))

      6.times do |i|
        drift = i * 0.00001
        make_point(at: base_ts + i * 30, lat: 52.5 + drift, lon: 13.4 + drift)
      end
      6.times do |i|
        drift = i * 0.00001
        make_point(at: base_ts + 900 + i * 30, lat: 52.5 + drift, lon: 13.4 + drift)
      end

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 1200).call

      expect(clusters.size).to eq(1)
    end
  end

  describe 'user-tunable minimum duration' do
    it 'respects visit_min_duration_minutes when raised above the default' do
      user.update!(settings: (user.settings || {}).merge('visit_min_duration_minutes' => 20))

      6.times do |i|
        drift = i * 0.00001
        make_point(at: base_ts + i * 60, lat: 52.5 + drift, lon: 13.4 + drift)
      end

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 400).call

      expect(clusters).to be_empty
    end

    it 'accepts shorter visits when visit_min_duration_minutes is lowered' do
      user.update!(settings: (user.settings || {}).merge('visit_min_duration_minutes' => 2))

      4.times do |i|
        drift = i * 0.00001
        make_point(at: base_ts + i * 60, lat: 52.5 + drift, lon: 13.4 + drift)
      end

      clusters = described_class.new(user, start_at: base_ts - 1, end_at: base_ts + 300).call

      expect(clusters.size).to eq(1)
    end
  end
end
