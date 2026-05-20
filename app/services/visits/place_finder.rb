# frozen_string_literal: true

module Visits
  class PlaceFinder
    SIMILARITY_RADIUS = 50

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def find_or_create_place(visit_data)
      lat = visit_data[:center_lat]
      lon = visit_data[:center_lon]

      existing = find_existing_place(lat, lon, visit_data[:suggested_name])
      return existing if existing

      create_default_place(lat, lon, visit_data[:suggested_name])
    end

    private

    def find_existing_place(lat, lon, name)
      by_location = user.places.near([lat, lon], SIMILARITY_RADIUS, :m).first
      return by_location if by_location

      return nil if name.blank?

      user.places.where(name: name).near([lat, lon], SIMILARITY_RADIUS * 2, :m).first
    end

    def create_default_place(lat, lon, suggested_name)
      place = user.places.create!(
        name:      suggested_name.presence || Place::DEFAULT_NAME,
        geodata:   {},
        latitude:  lat,
        longitude: lon,
        lonlat:    "POINT(#{lon} #{lat})",
        source:    :photon
      )

      Places::NameFetchingJob.perform_later(place.id) if DawarichSettings.reverse_geocoding_enabled?
      place
    end
  end
end
