# frozen_string_literal: true

module Achievements
  class LoadRegions
    class MissingCountriesError < StandardError; end

    ASSET_PATH = 'lib/assets/admin1_world.geojson'
    CODE_PROPERTY = 'iso_3166_2'
    MISSING_COUNTRIES = 'countries table is empty: run db/seeds.rb before loading achievement ' \
                        'regions, country-level achievements resolve through Country#iso_a2'

    def call
      raise MissingCountriesError, MISSING_COUNTRIES if Country.none?

      rows.each_slice(500) do |batch|
        Region.upsert_all(batch, unique_by: :code, update_only: %i[geom])
      end
    end

    private

    def rows
      now = Time.current

      features.map do |feature|
        { code: feature.properties[CODE_PROPERTY], geom: multi_polygon(feature.geometry),
          created_at: now, updated_at: now }
      end
    end

    def features
      RGeo::GeoJSON.decode(File.read(Rails.root.join(ASSET_PATH)), geo_factory: factory)
    end

    def factory
      @factory ||= RGeo::Geos.factory(srid: 4326)
    end

    def multi_polygon(geom)
      geom.geometry_type == RGeo::Feature::Polygon ? factory.multi_polygon([geom]) : geom
    end
  end
end
