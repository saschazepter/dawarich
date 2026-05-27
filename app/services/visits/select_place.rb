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
      @visit.with_lock do
        place = find_by_name_and_proximity || create_place
        @visit.update!(place_id: place.id, name: place.name)
        place
      end
    end

    private

    def find_by_name_and_proximity
      name = @photon[:name]
      lat = @photon[:latitude].to_f
      lon = @photon[:longitude].to_f
      return nil if name.blank?

      @user.places
           .includes(:tags)
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

      place = @user.places.create!(
        name: @photon[:name],
        latitude: lat,
        longitude: lon,
        lonlat: "POINT(#{lon} #{lat})",
        city: @photon[:city],
        country: @photon[:country],
        geodata: DawarichSettings.store_geodata? ? (@photon[:geodata] || {}) : {},
        source: :photon
      )

      %i[tags visits].each do |assoc|
        place.association(assoc).target = []
        place.association(assoc).loaded!
      end
      place
    end
  end
end
