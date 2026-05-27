# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Merger do
  let(:user) { create(:user) }

  describe '#merge_visits' do
    context 'when visits can be merged' do
      # visit1 and visit2 have centers ~15m apart (well within 50m threshold)
      # and a small time gap (10 minutes, well within 30 minute threshold)
      let(:points) { user.points.order(timestamp: :asc) }
      let!(:point1) { create(:point, user: user, timestamp: 2.hours.ago.to_i) }
      let!(:point2) { create(:point, user: user, timestamp: 50.minutes.ago.to_i) }

      let(:visit1) do
        {
          start_time: 2.hours.ago.to_i,
          end_time: 1.hour.ago.to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          points: [point1]
        }
      end

      # Very close to visit1 center (~15m away), small time gap
      let(:visit2) do
        {
          start_time: 50.minutes.ago.to_i,
          end_time: 40.minutes.ago.to_i,
          center_lat: 40.71290,
          center_lon: -74.00610,
          points: [point2]
        }
      end

      # Far from visit1/visit2 center (~4km away), should not merge
      let(:visit3) do
        {
          start_time: 30.minutes.ago.to_i,
          end_time: 20.minutes.ago.to_i,
          center_lat: 40.7500,
          center_lon: -74.0500,
          points: [double('Point5')]
        }
      end

      let(:visits) { [visit1, visit2, visit3] }

      subject { described_class.new(points) }

      it 'merges consecutive visits that meet criteria' do
        merged = subject.merge_visits(visits)

        expect(merged.size).to eq(2)
        expect(merged.first[:points].size).to eq(2)
        expect(merged.first[:end_time]).to eq(visit2[:end_time])
        expect(merged.last).to eq(visit3)
      end
    end

    context 'when visits cannot be merged' do
      let(:points) { user.points.order(timestamp: :asc) }

      # All visits have centers far apart (>50m threshold)
      let(:visit1) do
        {
          start_time: 2.hours.ago.to_i,
          end_time: 1.hour.ago.to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          points: [double('Point1')]
        }
      end

      let(:visit2) do
        {
          start_time: 50.minutes.ago.to_i,
          end_time: 40.minutes.ago.to_i,
          center_lat: 40.7500,
          center_lon: -74.0500,
          points: [double('Point3')]
        }
      end

      let(:visit3) do
        {
          start_time: 30.minutes.ago.to_i,
          end_time: 20.minutes.ago.to_i,
          center_lat: 40.8000,
          center_lon: -74.1000,
          points: [double('Point5')]
        }
      end

      let(:visits) { [visit1, visit2, visit3] }

      subject { described_class.new(points) }

      it 'keeps visits separate' do
        merged = subject.merge_visits(visits)

        expect(merged.size).to eq(3)
        expect(merged).to eq(visits)
      end
    end

    context 'with empty visits array' do
      let(:points) { user.points.order(timestamp: :asc) }

      subject { described_class.new(points) }

      it 'returns an empty array' do
        expect(subject.merge_visits([])).to eq([])
      end
    end

    context 'with a custom max_gap kwarg' do
      let(:points) { user.points.order(timestamp: :asc) }
      let(:base_ts) { 1_700_000_000 }
      let(:visit_a) do
        {
          start_time: base_ts,
          end_time: base_ts + 600,
          center_lat: 40.7128, center_lon: -74.0060,
          points: []
        }
      end
      let(:visit_b) do
        {
          start_time: base_ts + 800,
          end_time: base_ts + 1400,
          center_lat: 40.7128, center_lon: -74.0060,
          points: []
        }
      end
      let(:visits) { [visit_a, visit_b] }

      it 'does NOT merge when the gap exceeds the configured max_gap' do
        merger = described_class.new(points, max_gap: 1.minute)

        merged = merger.merge_visits(visits)

        expect(merged.size).to eq(2)
      end

      it 'merges when the gap is within the configured max_gap' do
        merger = described_class.new(points, max_gap: 60.minutes)

        merged = merger.merge_visits(visits)

        expect(merged.size).to eq(1)
        expect(merged.first[:end_time]).to eq(visit_b[:end_time])
      end

      it 'defaults max_gap to MAXIMUM_VISIT_GAP when not provided' do
        merger = described_class.new(points)

        expect(merger.max_gap).to eq(Visits::Merger::MAXIMUM_VISIT_GAP)
      end
    end
  end
end
