# frozen_string_literal: true

module Maps
  class PrivacyZoneMasker
    Circle = Struct.new(:lon, :lat, :radius_meters)

    def initialize(user)
      @user = user
    end

    def any?
      circles.any?
    end

    def mask_points(relation)
      mask_relation(relation, 'points.lonlat')
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
          Circle.new(place.longitude.to_f, place.latitude.to_f, tag.privacy_radius_meters)
        end
      end
    end
  end
end
