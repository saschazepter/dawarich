# frozen_string_literal: true

class Trips::CalculateCountriesJob < ApplicationJob
  queue_as :trips

  retry_on Timeout::Error, ActiveRecord::Deadlocked, attempts: 3

  discard_on StandardError do |job, error|
    trip_id = job.arguments.first
    Rails.logger.error("Trips::CalculateCountriesJob discarded trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, error: true)
  end

  def perform(trip_id, distance_unit)
    trip = Trip.find(trip_id)

    trip.calculate_countries
    trip.save!

    broadcast_update(trip, distance_unit)
    Trips::CalculateAllJob.tally_completion(trip_id)
  end

  private

  def broadcast_update(trip, distance_unit)
    Turbo::StreamsChannel.broadcast_update_to(
      "trip_#{trip.id}",
      target: 'trip_countries',
      partial: 'trips/countries',
      locals: { trip: trip, distance_unit: distance_unit }
    )
  end
end
