# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TimeChunkProcessorJob, type: :job do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end

  let(:chunk_start) { Time.zone.local(2026, 1, 1, 12, 0, 0).to_i }
  let(:chunk_end)   { Time.zone.local(2026, 1, 1, 12, 30, 0).to_i }

  let(:chunk_data) do
    {
      chunk_id: 'test-chunk-id',
      start_timestamp: chunk_start,
      end_timestamp: chunk_end,
      buffer_start_timestamp: chunk_start,
      buffer_end_timestamp: chunk_end,
      untracked_only: false
    }
  end

  before do
    session_manager = instance_double(
      Tracks::SessionManager,
      session_exists?: true,
      session_id: 'test-session'
    )
    allow(session_manager).to receive(:increment_completed_chunks)
    allow(session_manager).to receive(:increment_tracks_created)
    allow(session_manager).to receive(:mark_failed)
    allow(Tracks::SessionManager).to receive(:new).and_return(session_manager)
    allow(ExceptionReporter).to receive(:call)
  end

  describe '#perform' do
    context 'when distance calculation raises an error' do
      before do
        create(:point, user: user, timestamp: chunk_start + 60,
                       latitude: 52.5200, longitude: 13.4050,
                       lonlat: 'POINT(13.4050 52.5200)')
        create(:point, user: user, timestamp: chunk_start + 120,
                       latitude: 52.5201, longitude: 13.4060,
                       lonlat: 'POINT(13.4060 52.5201)')
        allow(Point).to receive(:calculate_distance_for_array_geocoder).and_raise(RuntimeError, 'boom')
      end

      it 'does not raise an error' do
        expect { described_class.perform_now(user.id, 'test-session', chunk_data) }.not_to raise_error
      end

      it 'reports the exception via ExceptionReporter' do
        described_class.perform_now(user.id, 'test-session', chunk_data)

        expect(ExceptionReporter).to have_received(:call).with(
          instance_of(RuntimeError),
          'Track creation failed for chunk test-chunk-id'
        )
      end

      it 'does not create any Track records' do
        expect { described_class.perform_now(user.id, 'test-session', chunk_data) }
          .not_to change(Track, :count)
      end
    end

    context 'when points are valid' do
      before do
        create(:point, user: user, timestamp: chunk_start + 60,
                       latitude: 52.5200, longitude: 13.4050,
                       lonlat: 'POINT(13.4050 52.5200)')
        create(:point, user: user, timestamp: chunk_start + 120,
                       latitude: 52.5201, longitude: 13.4060,
                       lonlat: 'POINT(13.4060 52.5201)')
        create(:point, user: user, timestamp: chunk_start + 180,
                       latitude: 52.5202, longitude: 13.4070,
                       lonlat: 'POINT(13.4070 52.5202)')
      end

      it 'creates at least one Track record' do
        expect { described_class.perform_now(user.id, 'test-session', chunk_data) }
          .to change(Track, :count).by_at_least(1)
      end
    end
  end
end
