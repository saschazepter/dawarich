# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::DbscanClusterer do
  let(:user) { create(:user) }

  describe 'synthetic-point cap' do
    it 'caps generated synthetic points at MAX_SYNTHETIC_PER_GAP per gap' do
      now = 1_700_000_000
      far_future = now + 24 * 3600
      create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: now, accuracy: 10, visit_id: nil)
      create(:point, user: user, latitude: 52.5001, longitude: 13.4001, lonlat: 'POINT(13.4001 52.5001)',
                     timestamp: far_future, accuracy: 10, visit_id: nil)

      clusters = described_class.new(user, start_at: now - 1, end_at: far_future + 1).call
      total_points = clusters.sum { |c| c[:point_count] }

      expect(total_points).to be <= described_class::MAX_SYNTHETIC_PER_GAP + 2
    end
  end

  describe 'connection state' do
    it 'sets and resets statement_timeout without opening a transaction' do
      timeouts = []
      original = ActiveRecord::Base.connection.method(:execute)
      allow(ActiveRecord::Base.connection).to receive(:execute) do |sql, *rest|
        timeouts << sql if sql.to_s.match?(/statement_timeout/i)
        original.call(sql, *rest)
      end

      open_before = ActiveRecord::Base.connection.open_transactions
      described_class.new(user, start_at: 0, end_at: 1).call
      open_after = ActiveRecord::Base.connection.open_transactions

      expect(timeouts.first).to match(/SET statement_timeout/i)
      expect(timeouts.last).to match(/RESET statement_timeout/i)
      expect(open_after).to eq(open_before)
    end
  end

  describe 'logging' do
    it 'emits a single structured INFO log on success' do
      ts = 1_700_000_000
      3.times do |i|
        create(:point, user: user, latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                       timestamp: ts + i * 60, accuracy: 10, visit_id: nil)
      end

      log_pattern = /\[Visits::DbscanClusterer\] user_id=#{user.id} range=\d+\.\.\d+ clusters=\d+ duration_ms=\d+/
      expect(Rails.logger).to receive(:info).with(a_string_matching(log_pattern))

      described_class.new(user, start_at: ts - 1, end_at: ts + 600).call
    end
  end
end
