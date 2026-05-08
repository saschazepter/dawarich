# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::CalculateAllJob, type: :job do
  let(:user) { create(:user) }
  let(:trip) do
    create(:trip,
           user: user,
           started_at: DateTime.new(2024, 11, 27, 12, 0, 0),
           ended_at: DateTime.new(2024, 11, 27, 14, 0, 0))
  end

  before do
    allow(Trips::CalculatePathJob).to receive(:perform_now)
    allow(Trips::CalculateDistanceJob).to receive(:perform_now)
    allow(Trips::CalculateCountriesJob).to receive(:perform_now)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe '#perform' do
    it 'runs the three sub-jobs synchronously in path -> distance -> countries order' do
      expect(Trips::CalculatePathJob).to receive(:perform_now).with(trip.id).ordered
      expect(Trips::CalculateDistanceJob).to receive(:perform_now).with(trip.id, 'km').ordered
      expect(Trips::CalculateCountriesJob).to receive(:perform_now).with(trip.id, 'km').ordered

      described_class.perform_now(trip.id, 'km')
    end

    it 'clears last_recalculated_at after success' do
      trip.update_column(:last_recalculated_at, Time.current)

      described_class.perform_now(trip.id, 'km')

      expect(trip.reload.last_recalculated_at).to be_nil
    end

    it 'broadcasts the recalculate-button frame replacement on success' do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "trip_#{trip.id}",
        hash_including(
          target: 'trip_recalculate_frame',
          partial: 'trips/recalculate_button',
          locals: hash_including(trip: trip, error: false)
        )
      )

      described_class.perform_now(trip.id, 'km')
    end

    it 'no-ops finalize cleanly when the trip has been deleted mid-run' do
      allow(Trips::CalculateCountriesJob).to receive(:perform_now) do
        trip.destroy!
      end

      expect { described_class.perform_now(trip.id, 'km') }.not_to raise_error
    end
  end

  describe 'permanent failure handling' do
    it 'broadcasts an error frame replacement after the retry budget is exhausted' do
      trip.update_column(:last_recalculated_at, Time.current)

      job = described_class.new(trip.id, 'km')
      job.send(:finalize, trip.id, error: true)

      expect(trip.reload.last_recalculated_at).to be_nil
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "trip_#{trip.id}",
        hash_including(locals: hash_including(error: true))
      )
    end
  end
end
