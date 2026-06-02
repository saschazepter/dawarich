# frozen_string_literal: true

module Maps
  class PrivacyZoneMasker
    Circle = Struct.new(:lon, :lat, :radius_meters, keyword_init: true)
    EARTH_RADIUS_M = 6_371_000.0

    delegate :any?, to: :circles

    def initialize(user)
      @user = user
    end

    def mask_points(relation)
      mask_relation(relation, 'points.lonlat')
    end

    def mask_places(relation)
      mask_relation(relation, 'places.lonlat')
    end

    def in_zone_place_ids
      return [] unless any?

      user.places.where(within_sql('places.lonlat'), *binds).pluck(:id)
    end

    def in_zone?(lon, lat)
      circles.any? { |c| haversine_m(lat, lon, c.lat, c.lon) <= c.radius_meters }
    end

    private

    attr_reader :user

    def mask_relation(relation, column)
      return relation unless any?

      relation.where("NOT (#{within_sql(column)})", *binds)
    end

    def within_sql(column)
      circles
        .map { "ST_DWithin(#{column}, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)" }
        .join(' OR ')
    end

    def binds
      circles.flat_map { |c| [c.lon, c.lat, c.radius_meters] }
    end

    def circles
      @circles ||= user.tags.privacy_zones.includes(:places).flat_map do |tag|
        tag.places.map do |place|
          Circle.new(lon: place.longitude.to_f, lat: place.latitude.to_f, radius_meters: tag.privacy_radius_meters)
        end
      end
    end

    def haversine_m(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180
      d_lat = (lat2 - lat1) * rad
      d_lon = (lon2 - lon1) * rad
      a = (Math.sin(d_lat / 2)**2) +
          (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(d_lon / 2)**2))
      2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))
    end
  end
end
