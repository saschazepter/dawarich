# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::RegionDwellCalculator do
  let(:user) { create(:user) }
  let!(:region) { create(:region, code: 'TT-01', geom: 'MULTIPOLYGON (((0 0, 0 1, 1 1, 1 0, 0 0)))') }
  let(:base_ts) { DateTime.new(2026, 1, 1).to_i }

  def create_point(lon, lat, offset_seconds, attrs = {})
    create(:point, user:, longitude: lon, latitude: lat, timestamp: base_ts + offset_seconds, **attrs)
  end

  describe '#call' do
    it 'accumulates dwell for consecutive pairs inside the same region' do
      create_point(0.5, 0.5, 0)
      create_point(0.6, 0.5, 600)
      create_point(0.7, 0.5, 1200)

      result = described_class.new(user, codes: ['TT-01']).call

      expect(result.deltas).to eq('TT-01' => 1200)
      expect(result.new_cursor).to eq(base_ts + 1200)
    end

    it 'caps a single pair at 30 minutes' do
      create_point(0.5, 0.5, 0)
      create_point(0.6, 0.5, 86_400)

      result = described_class.new(user, codes: ['TT-01']).call

      expect(result.deltas).to eq('TT-01' => 1800)
    end

    it 'ignores pairs spanning region boundary' do
      create_point(0.5, 0.5, 0)
      create_point(5.0, 5.0, 600)

      result = described_class.new(user, codes: ['TT-01']).call

      expect(result.deltas).to eq({})
    end

    it 'excludes anomaly points' do
      create_point(0.5, 0.5, 0)
      create_point(0.6, 0.5, 600, anomaly: true)
      create_point(0.7, 0.5, 1200)

      result = described_class.new(user, codes: ['TT-01']).call

      expect(result.deltas).to eq('TT-01' => 1200)
    end

    it 'returns nil when no points are newer than the cursor' do
      create_point(0.5, 0.5, 0)
      first = described_class.new(user, codes: ['TT-01']).call

      expect(described_class.new(user, codes: ['TT-01'], since: first.new_cursor).call).to be_nil
    end

    it 'counts the cursor-straddling pair exactly once across incremental runs' do
      create_point(0.5, 0.5, 0)
      create_point(0.6, 0.5, 600)
      first = described_class.new(user, codes: ['TT-01']).call

      create_point(0.7, 0.5, 1200)
      second = described_class.new(user, codes: ['TT-01'], since: first.new_cursor).call

      expect(first.deltas.fetch('TT-01', 0) + second.deltas.fetch('TT-01', 0)).to eq(1200)
    end
  end
end
