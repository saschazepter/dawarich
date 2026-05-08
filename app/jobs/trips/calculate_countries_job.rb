# frozen_string_literal: true

class Trips::CalculateCountriesJob < ApplicationJob
  queue_as :trips

  def perform(trip_id, distance_unit)
    trip = Trip.find(trip_id)

    trip.calculate_countries
    trip.last_recalculated_at = nil if trip.last_recalculated_at.present?
    trip.save!

    broadcast_update(trip, distance_unit)
    broadcast_recalculate_button(trip)
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

  def broadcast_recalculate_button(trip)
    Turbo::StreamsChannel.broadcast_replace_to(
      "trip_#{trip.id}",
      target: 'trip_recalculate_frame',
      partial: 'trips/recalculate_button',
      locals: { trip: trip }
    )
  end
end
