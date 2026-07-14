# frozen_string_literal: true

module Achievements
  class LoadRegions
    ASSET_PATH = 'lib/assets/admin1_regions.geojson'

    def call
      factory = RGeo::Geos.factory(srid: 4326)
      features = RGeo::GeoJSON.decode(File.read(Rails.root.join(ASSET_PATH)), geo_factory: factory)

      ActiveRecord::Base.transaction do
        features.each do |feature|
          code = feature.properties['iso_3166_2']
          geom = feature.geometry
          geom = factory.multi_polygon([geom]) if geom.geometry_type == RGeo::Feature::Polygon

          Region.find_or_create_by!(code: code) { |region| region.geom = geom }
        end
      end
    end
  end
end
