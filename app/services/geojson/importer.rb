# frozen_string_literal: true

class Geojson::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include PointValidation

  BATCH_SIZE = 1000
  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import  = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = load_json_data
    parsed = Geojson::Params.new(json).call

    points_count = import_points(parsed[:points])
    places_count = Places::GeojsonPointImporter.new(import, user_id, parsed[:place_features]).call

    return unless parsed[:has_timeless_track] && points_count.zero? && places_count.zero?

    raise Imports::NoTimestampsError
  end

  private

  def import_points(points)
    return 0 if points.blank?

    total_inserted = 0
    points_data = points.map do |point|
      next if point[:lonlat].nil?

      point.merge(
        user_id: user_id,
        import_id: import.id,
        created_at: Time.current,
        updated_at: Time.current
      )
    end.compact

    points_data.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      total_inserted += bulk_insert_points(batch)
      broadcast_import_progress(import, (batch_index + 1) * BATCH_SIZE)
    end

    total_inserted
  end

  def importer_name
    'GeoJSON'
  end
end
