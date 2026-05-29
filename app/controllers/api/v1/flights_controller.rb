# frozen_string_literal: true

class Api::V1::FlightsController < ApiController
  def index
    flights = current_api_user.flights
    flights = apply_date_filter(flights)

    render json: {
      type: 'FeatureCollection',
      features: flights.map { |flight| Api::FlightSerializer.new(flight).call }
    }
  end

  private

  def apply_date_filter(flights)
    return flights if params[:start_at].blank? && params[:end_at].blank?

    start_at = params[:start_at].present? ? Time.zone.parse(params[:start_at].to_s) : Time.zone.at(0)
    end_at = params[:end_at].present? ? Time.zone.parse(params[:end_at].to_s) : Time.zone.now
    flights.where(departure_time: start_at..end_at)
  end
end
