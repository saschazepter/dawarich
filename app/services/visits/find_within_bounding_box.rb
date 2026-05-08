# frozen_string_literal: true

module Visits
  # Finds visits in a selected area on the map
  class FindWithinBoundingBox
    def initialize(user, params)
      @user = user
      @sw_lat = params[:sw_lat].to_f
      @sw_lng = params[:sw_lng].to_f
      @ne_lat = params[:ne_lat].to_f
      @ne_lng = params[:ne_lng].to_f
    end

    PLACE_INSIDE = 'places.lonlat IS NOT NULL AND ' \
                   'ST_Contains(ST_MakeEnvelope(?, ?, ?, ?, 4326), ' \
                   'ST_SetSRID(places.lonlat::geometry, 4326))'

    AREA_INSIDE = 'areas.id IS NOT NULL AND ' \
                  'ST_Contains(ST_MakeEnvelope(?, ?, ?, ?, 4326), ' \
                  'ST_SetSRID(ST_MakePoint(areas.longitude, areas.latitude), 4326))'

    def call
      user.scoped_visits
          .includes(:place, :area)
          .left_outer_joins(:place, :area)
          .where(
            "(#{PLACE_INSIDE}) OR (#{AREA_INSIDE})",
            sw_lng, sw_lat, ne_lng, ne_lat,
            sw_lng, sw_lat, ne_lng, ne_lat
          )
          .order(started_at: :desc)
    end

    private

    attr_reader :user, :sw_lat, :sw_lng, :ne_lat, :ne_lng
  end
end
