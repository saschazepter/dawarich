# frozen_string_literal: true

class Trips::CalculateAllJob < ApplicationJob
  queue_as :trips

  PENDING_KEY_PREFIX = 'trips:recalc:pending'
  PENDING_TTL = 10.minutes

  def perform(trip_id, distance_unit = 'km')
    Rails.cache.write(self.class.pending_key(trip_id), 3, expires_in: PENDING_TTL, raw: true)

    Trips::CalculatePathJob.perform_later(trip_id)
    Trips::CalculateDistanceJob.perform_later(trip_id, distance_unit)
    Trips::CalculateCountriesJob.perform_later(trip_id, distance_unit)
  end

  def self.pending_key(trip_id)
    "#{PENDING_KEY_PREFIX}:#{trip_id}"
  end

  def self.tally_completion(trip_id, error: false)
    key = pending_key(trip_id)
    return unless Rails.cache.read(key, raw: true)

    if error
      Rails.cache.delete(key)
      finalize(trip_id, error: true)
      return
    end

    remaining = Rails.cache.decrement(key)
    return if remaining.nil? || remaining.positive?

    Rails.cache.delete(key)
    finalize(trip_id, error: false)
  end

  def self.finalize(trip_id, error:)
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
