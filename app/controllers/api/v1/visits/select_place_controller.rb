# frozen_string_literal: true

class Api::V1::Visits::SelectPlaceController < ApiController
  class InvalidCoordinate < StandardError; end

  def create
    visit = current_api_user.visits.find(params[:id])
    place = Visits::SelectPlace.new(user: current_api_user, visit: visit, photon: photon_params).call
    render json: serialize_place(place), status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Visit not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing, InvalidCoordinate => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def photon_params
    params.require(:photon).permit(
      :name, :latitude, :longitude,
      :osm_id, :osm_type, :osm_key, :osm_value,
      :city, :country, :street, :housenumber, :postcode,
      geodata: {}
    ).tap do |p|
      raise ActionController::ParameterMissing, :name      if p[:name].blank?
      raise ActionController::ParameterMissing, :latitude  if p[:latitude].blank?
      raise ActionController::ParameterMissing, :longitude if p[:longitude].blank?

      lat = p[:latitude].to_f
      lon = p[:longitude].to_f
      raise InvalidCoordinate, 'latitude out of range [-90, 90]'    unless lat.between?(-90, 90)
      raise InvalidCoordinate, 'longitude out of range [-180, 180]' unless lon.between?(-180, 180)
    end
  end

  def serialize_place(place)
    tags = place.tags.to_a
    first_tag = tags.first

    {
      id: place.id,
      name: place.name,
      latitude: place.lat,
      longitude: place.lon,
      source: place.source,
      note: place.note,
      icon: first_tag&.icon,
      color: first_tag&.color,
      visits_count: place.visits.size,
      created_at: place.created_at,
      tags: tags.map do |tag|
        {
          id: tag.id,
          name: tag.name,
          icon: tag.icon,
          color: tag.color,
          privacy_radius_meters: tag.privacy_radius_meters
        }
      end
    }
  end
end
