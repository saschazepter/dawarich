# frozen_string_literal: true

class Map::LeafletController < ApplicationController
  include SafeTimestampParser

  before_action :authenticate_user!
  layout 'map', only: :index

  def index
    @points = filtered_points
    @coordinates = build_coordinates
    @tracks = build_tracks
    @distance = calculate_distance
    @start_at = parsed_start_at
    @end_at = parsed_end_at
    @years = years_range
    @points_number = points_count
    @features = DawarichSettings.features
    @home_coordinates = current_user.home_place_coordinates
  end

  private

  def filtered_points
    points.where('timestamp >= ? AND timestamp <= ?', start_at, end_at)
  end

  def build_coordinates
    @points.pluck(:lonlat, :battery, :altitude, :timestamp, :velocity, :id, :country_name, :track_id)
           .map { |lonlat, *rest| [lonlat.y, lonlat.x, *rest.map(&:to_s)] }
  end

  def extract_track_ids
    @coordinates.map { |coord| coord[8]&.to_i }.compact.uniq.reject(&:zero?)
  end

  def build_tracks
    track_ids = extract_track_ids

    TracksSerializer.new(current_user, track_ids).call
  end

  def calculate_distance
    return 0 if @points.count(:id) < 2

    # Use PostGIS window function for efficient distance calculation
    # This is O(1) database operation vs O(n) Ruby iteration
    import_filter = params[:import_id].present? ? 'AND import_id = :import_id' : ''

    sql = <<~SQL.squish
      SELECT COALESCE(SUM(distance_m) / 1000.0, 0) as total_km FROM (
        SELECT ST_Distance(
          lonlat::geography,
          LAG(lonlat::geography) OVER (ORDER BY timestamp)
        ) as distance_m
        FROM points
        WHERE user_id = :user_id
          AND timestamp >= :start_at
          AND timestamp <= :end_at
          #{import_filter}
      ) distances
    SQL

    query_params = { user_id: current_user.id, start_at: start_at, end_at: end_at }
    query_params[:import_id] = params[:import_id] if params[:import_id].present?

    result = Point.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([sql, query_params])
    )

    result&.to_f&.round || 0
  end

  def parsed_start_at
    Time.zone.at(start_at)
  end

  def parsed_end_at
    Time.zone.at(end_at)
  end

  def years_range
    (parsed_start_at.year..parsed_end_at.year).to_a
  end

  def points_count
    @coordinates.count
  end

  def start_at
    return safe_timestamp(params[:start_at]) if params[:start_at].present?
    return import_window_start if import_window_start

    last_timestamp = points.last&.timestamp
    return Time.zone.at(last_timestamp).beginning_of_day.to_i if last_timestamp

    Time.zone.today.beginning_of_day.to_i
  end

  def end_at
    return safe_timestamp(params[:end_at]) if params[:end_at].present?
    return import_window_end if import_window_end

    last_timestamp = points.last&.timestamp
    return Time.zone.at(last_timestamp).end_of_day.to_i if last_timestamp

    Time.zone.today.end_of_day.to_i
  end

  def import_window_start
    return @import_window_start if defined?(@import_window_start)

    ts = import_record&.points&.minimum(:timestamp)
    @import_window_start = ts ? Time.zone.at(ts).beginning_of_day.to_i : nil
  end

  def import_window_end
    return @import_window_end if defined?(@import_window_end)

    ts = import_record&.points&.maximum(:timestamp)
    @import_window_end = ts ? Time.zone.at(ts).end_of_day.to_i : nil
  end

  def import_record
    return @import_record if defined?(@import_record)

    @import_record = params[:import_id].present? ? current_user.imports.find_by(id: params[:import_id]) : nil
  end

  def points
    params[:import_id] ? points_from_import : points_from_user
  end

  def points_from_import
    current_user.imports.find(params[:import_id]).points.without_raw_data.order(timestamp: :asc)
  end

  def points_from_user
    current_user.scoped_points.without_raw_data.order(timestamp: :asc)
  end
end
