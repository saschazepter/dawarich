# frozen_string_literal: true

module EnhancedImport
  module Writers
    class PlaceWriter
      def initialize(user)
        @user = user
      end

      def upsert(extracted)
        existing = Place.where(user_id: @user.id)
                        .where("geodata ->> 'external_place_id' = ?", extracted.external_place_id)
                        .first
        return [existing, false] if existing

        place = Place.create!(
          user_id: @user.id,
          name: extracted.name.presence || 'Unknown',
          latitude: extracted.latitude,
          longitude: extracted.longitude,
          lonlat: "POINT(#{extracted.longitude} #{extracted.latitude})",
          geodata: build_geodata(extracted)
        )
        [place, true]
      rescue ActiveRecord::RecordNotUnique
        existing = Place.where(user_id: @user.id)
                        .where("geodata ->> 'external_place_id' = ?", extracted.external_place_id)
                        .first
        [existing, false]
      end

      private

      def build_geodata(extracted)
        {
          'external_place_id' => extracted.external_place_id,
          'semantic_type' => extracted.semantic_type
        }.merge(extracted.geodata_extras || {}).compact
      end
    end
  end
end
