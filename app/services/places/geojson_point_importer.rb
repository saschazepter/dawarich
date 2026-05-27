# frozen_string_literal: true

class Places::GeojsonPointImporter
  BATCH_SIZE = 500
  DEFAULT_NAME = 'Imported place'

  attr_reader :import, :user_id, :features, :imported_count

  def initialize(import, user_id, features)
    @import = import
    @user_id = user_id
    @features = features
    @imported_count = 0
  end

  def call
    return 0 if features.blank?

    features.each_slice(BATCH_SIZE) do |slice|
      rows = slice.filter_map { |feature| prepare_place(feature) }
      next if rows.empty?

      result = Place.insert_all(rows)
      @imported_count += result.length
    end

    imported_count
  end

  private

  def prepare_place(feature)
    coordinates = feature.dig(:geometry, :coordinates) || feature.dig('geometry', 'coordinates')
    return if coordinates.blank? || coordinates[0].nil? || coordinates[1].nil?

    properties = feature[:properties] || feature['properties'] || {}
    name = properties[:name].presence || properties['name'].presence || DEFAULT_NAME

    longitude = coordinates[0].to_f.round(6)
    latitude  = coordinates[1].to_f.round(6)

    {
      name: name.to_s.strip,
      latitude: latitude,
      longitude: longitude,
      lonlat: "POINT(#{longitude} #{latitude})",
      source: Place.sources[:geojson_point],
      user_id: user_id,
      geodata: {},
      created_at: Time.current,
      updated_at: Time.current
    }
  end
end
