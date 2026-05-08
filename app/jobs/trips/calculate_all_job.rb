# frozen_string_literal: true

class Trips::CalculateAllJob < ApplicationJob
  queue_as :trips

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.error("Trips::CalculateAllJob permanent failure trip_id=#{job.arguments.first}: #{error.class}: #{error.message}")
    job.send(:finalize, job.arguments.first, error: true)
  end

  def perform(trip_id, distance_unit = 'km')
    Trips::CalculatePathJob.perform_now(trip_id)
    Trips::CalculateDistanceJob.perform_now(trip_id, distance_unit)
    Trips::CalculateCountriesJob.perform_now(trip_id, distance_unit)

    finalize(trip_id, error: false)
  end

  private

  def finalize(trip_id, error:)
    trip = Trip.find_by(id: trip_id)
    return unless trip

    trip.update_columns(last_recalculated_at: nil) if trip.last_recalculated_at.present?

    Turbo::StreamsChannel.broadcast_replace_to(
      "trip_#{trip.id}",
      target: 'trip_recalculate_frame',
      partial: 'trips/recalculate_button',
      locals: { trip: trip, error: error }
    )
  end
end
