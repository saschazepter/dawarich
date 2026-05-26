# frozen_string_literal: true

module Visits
  class SelectPlace
    PROXIMITY_METERS = 50
    LOCK_TTL = 30.seconds
    LOCK_ACQUIRE_TIMEOUT = 5.seconds

    def initialize(user:, visit:, photon:)
      @user = user
      @visit = visit
      @photon = photon.respond_to?(:with_indifferent_access) ? photon.with_indifferent_access : photon
    end

    def call
      with_dedup_lock do
        place = find_by_name_and_proximity || create_place
        @visit.update!(place_id: place.id, name: place.name)
        place
      end
    end

    private

    def with_dedup_lock(&block)
      # Per-suggestion key so two parallel selections for DIFFERENT Photon
      # suggestions for the same user (e.g. web + mobile both submitting
      # different places) run in parallel; only SAME-suggestion calls serialize.
      ident = @photon[:osm_id].presence || "#{@photon[:name]}:#{@photon[:latitude]}:#{@photon[:longitude]}"
      Tracks::PerUserLock.with_user_lock(
        "select_place:#{@user.id}:#{ident}",
        ttl: LOCK_TTL,
        timeout: LOCK_ACQUIRE_TIMEOUT,
        &block
      )
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
