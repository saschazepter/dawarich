# frozen_string_literal: true

module Visits
  class SelectPlacesController < ApplicationController
    class InvalidCoordinate < StandardError; end

    include FlashStreamable

    before_action :authenticate_user!
    before_action :set_visit

    def create
      ::Visits::SelectPlace.new(user: current_user, visit: @visit, photon: photon_params).call

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:notice, 'Place selected.')
        end
        format.html { redirect_back(fallback_location: '/map/v2?panel=timeline&date=today&status=suggested') }
      end
    rescue ActionController::ParameterMissing, InvalidCoordinate => e
      respond_to do |format|
        format.turbo_stream { render turbo_stream: stream_flash(:error, e.message) }
        format.html { redirect_back(fallback_location: '/map/v2?panel=timeline&date=today&status=suggested') }
      end
    end

    private

    def set_visit
      @visit = current_user.visits.find(params[:id])
    end

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
  end
end
