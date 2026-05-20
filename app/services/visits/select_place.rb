# frozen_string_literal: true

module Visits
  class SelectPlace
    PROXIMITY_METERS = 50

    def initialize(user:, visit:, photon:)
      @user = user
      @visit = visit
      @photon = photon.respond_to?(:with_indifferent_access) ? photon.with_indifferent_access : photon
    end

    def call
      place = find_by_osm_id || find_by_name_and_proximity || create_place
      @visit.update!(place_id: place.id, name: place.name)
      place
    end

    private

    def find_by_osm_id
      osm_id = @photon[:osm_id]
      return nil if osm_id.blank?

      @user.places
           .where("geodata->'properties'->>'osm_id' = ?", osm_id.to_s)
           .first
    end

    def find_by_name_and_proximity
      name = @photon[:name]
      lat = @photon[:latitude].to_f
      lon = @photon[:longitude].to_f
      return nil if name.blank?

      @user.places
           .where(name: name)
           .where(
             'ST_DWithin(lonlat::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
             lon, lat, PROXIMITY_METERS
           )
           .first
    end

    def create_place
      lat = @photon[:latitude].to_f
      lon = @photon[:longitude].to_f

      @user.places.create!(
        name: @photon[:name],
        latitude: lat,
        longitude: lon,
        lonlat: "POINT(#{lon} #{lat})",
        city: @photon[:city],
        country: @photon[:country],
        geodata: DawarichSettings.store_geodata? ? (@photon[:geodata] || {}) : {},
        source: :photon
      )
    end
  end
end
