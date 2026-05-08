# frozen_string_literal: true

class Trips::CalculatePathJob < ApplicationJob
  queue_as :trips

  retry_on Timeout::Error, ActiveRecord::Deadlocked, attempts: 3

  discard_on StandardError do |job, error|
    trip_id = job.arguments.first
    Rails.logger.error("Trips::CalculatePathJob discarded trip_id=#{trip_id}: #{error.class}: #{error.message}")
    Trips::CalculateAllJob.tally_completion(trip_id, error: true)
  end

  def perform(trip_id)
    trip = Trip.find(trip_id)

    trip.calculate_path
    trip.save!

    broadcast_update(trip)
    Trips::CalculateAllJob.tally_completion(trip_id)
  end

  private

  def broadcast_update(trip)
    Turbo::StreamsChannel.broadcast_update_to(
      "trip_#{trip.id}",
      target: 'trip_path',
      partial: 'trips/path',
      locals: { trip: trip }
    )
  end
end
