# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSegments::BulkInserter do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  let(:segment_data) do
    [
      {
        mode: :walking,
        start_index: 0,
        end_index: 5,
        distance: 500,
        duration: 300,
        avg_speed: 5.0,
        max_speed: 7.0,
        avg_acceleration: 0.1,
        confidence: :medium,
        source: 'inferred'
      },
      {
        mode: :driving,
        start_index: 6,
        end_index: 20,
        distance: 12_000,
        duration: 600,
        avg_speed: 30.0,
        max_speed: 50.0,
        avg_acceleration: 0.5,
        confidence: :high,
        source: 'inferred'
      }
    ]
  end

  describe '.call' do
    it 'creates one row per segment' do
      expect { described_class.call(track, segment_data) }
        .to change { track.track_segments.count }.from(0).to(2)
    end

    it 'writes attributes to the database' do
      described_class.call(track, segment_data)

      walking, driving = track.track_segments.order(:start_index).to_a

      expect(walking).to have_attributes(
        transportation_mode: 'walking',
        start_index: 0,
        end_index: 5,
        distance: 500,
        duration: 300,
        avg_speed: 5.0,
        max_speed: 7.0,
        confidence: 'medium',
        source: 'inferred'
      )
      expect(driving).to have_attributes(
        transportation_mode: 'driving',
        start_index: 6,
        end_index: 20,
        confidence: 'high'
      )
    end

    it 'issues a single INSERT' do
      queries = []
      callback = ->(_n, _s, _f, _i, payload) { queries << payload[:sql] if payload[:sql].start_with?('INSERT') }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        described_class.call(track, segment_data)
      end

      inserts = queries.count { |sql| sql.include?('"track_segments"') }
      expect(inserts).to eq(1)
    end

    it 'sets created_at and updated_at' do
      described_class.call(track, segment_data)
      track.track_segments.each do |segment|
        expect(segment.created_at).to be_within(5.seconds).of(Time.current)
        expect(segment.updated_at).to be_within(5.seconds).of(Time.current)
      end
    end

    it 'returns the original segment data' do
      result = described_class.call(track, segment_data)
      expect(result).to eq(segment_data)
    end

    it 'returns empty array and writes nothing when segment_data is empty' do
      expect { described_class.call(track, []) }
        .not_to(change { TrackSegment.count })
      expect(described_class.call(track, [])).to eq([])
    end

    it 'raises KeyError for an unknown transportation mode' do
      bad_data = [segment_data.first.merge(mode: :teleportation)]
      expect { described_class.call(track, bad_data) }.to raise_error(KeyError)
    end

    it 'raises KeyError for an unknown confidence value' do
      bad_data = [segment_data.first.merge(confidence: :certain)]
      expect { described_class.call(track, bad_data) }.to raise_error(KeyError)
    end
  end
end
