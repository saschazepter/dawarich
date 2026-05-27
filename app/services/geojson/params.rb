# frozen_string_literal: true

class Geojson::Params
  include Imports::FieldAliases

  attr_reader :json

  def initialize(json)
    @json = json.with_indifferent_access
  end

  def call
    classified = classify_root(json)
    {
      points: classified.select { |row| row[:kind] == :point }.map { |row| row[:attrs] },
      place_features: classified.select { |row| row[:kind] == :place_feature }.map { |row| row[:feature] },
      has_timeless_track: classified.any? { |row| row[:kind] == :timeless_track }
    }
  end

  private

  def classify_root(json)
    case json[:type]
    when 'Feature' then classify_feature(json)
    when 'FeatureCollection' then Array(json[:features]).flat_map { |feature| classify_feature(feature) }
    else []
    end
  end

  def classify_feature(feature)
    return [] if feature[:geometry].blank?

    case feature[:geometry][:type]
    when 'Point'           then classify_point(feature)
    when 'LineString'      then classify_line(feature)
    when 'MultiLineString' then classify_multi_line(feature)
    else []
    end
  end

  def classify_point(feature)
    attrs = build_point(feature)
    return [{ kind: :place_feature, feature: feature }] if attrs[:timestamp].nil?

    [{ kind: :point, attrs: attrs }]
  end

  def classify_line(feature)
    points = feature[:geometry][:coordinates].map { |point| build_line_point(point) }
    materialise_line_points(points)
  end

  def classify_multi_line(feature)
    points = feature[:geometry][:coordinates].flat_map do |line|
      line.map { |point| build_line_point(point) }
    end
    materialise_line_points(points)
  end

  def materialise_line_points(points)
    valid = points.select { |attrs| attrs[:timestamp].present? }
    return [{ kind: :timeless_track }] if valid.empty? && points.any?

    valid.map { |attrs| { kind: :point, attrs: attrs } }
  end

  def build_point(feature)
    properties = feature[:properties]
    altitude_value = altitude(feature)

    attrs = {
      lonlat:             "POINT(#{feature[:geometry][:coordinates][0]} #{feature[:geometry][:coordinates][1]})",
      battery_status:     properties[:battery_state],
      battery:            battery(properties),
      timestamp:          timestamp(feature),
      altitude:           altitude_value,
      velocity:           speed(properties),
      tracker_id:         find_field(properties, :tracker_id),
      ssid:               properties[:wifi],
      accuracy:           find_field(properties, :accuracy),
      vertical_accuracy:  find_field(properties, :vertical_accuracy),
      course:             find_field(properties, :heading),
      motion_data:        Points::MotionDataExtractor.from_overland_properties(properties),
      raw_data:           feature
    }
    attrs[:altitude_decimal] = altitude_value if Point.altitude_decimal_supported?
    attrs
  end

  def build_line_point(point)
    {
      lonlat: "POINT(#{point[0]} #{point[1]})",
      timestamp: timestamp(point),
      raw_data:  point
    }
  end

  def battery(properties)
    value = find_field(properties, :battery)
    return nil if value.nil?

    numeric = value.to_f
    # Values <= 1.0 are fractional (e.g. 0.72 = 72%), convert to percentage
    numeric = (numeric * 100).to_i if numeric <= 1.0 && numeric.positive?
    numeric.to_i >= 0 ? numeric.to_i : nil
  end

  def altitude(feature)
    find_field(feature[:properties], :altitude) || feature.dig(:geometry, :coordinates, 2)
  end

  def timestamp(feature)
    if feature.is_a?(Array)
      return parse_array_timestamp(feature[3]) if feature[3].present?

      return nil
    end

    numeric_timestamp(feature) || parse_string_timestamp(feature)
  end

  def parse_array_timestamp(value)
    return value.to_i if value.is_a?(Numeric)

    Time.zone.parse(value.to_s)&.utc&.to_i if value.present?
  end

  def numeric_timestamp(feature)
    value = find_field(feature[:properties], :timestamp)
    value ||= feature.dig(:geometry, :coordinates, 3)

    return nil unless value.is_a?(Numeric)

    # Unix milliseconds: divide by 1000 if value is too large for seconds
    value /= 1000.0 if value > 10_000_000_000
    value.to_i
  end

  def parse_string_timestamp(feature)
    time = find_field(feature[:properties], :timestamp)

    Time.zone.parse(time.to_s).utc.to_i if time.present?
  end

  def speed(properties)
    value, matched_key = find_field_with_key(properties, :speed)
    return 0.0 if value.nil?

    numeric = value.to_f
    numeric /= 3.6 if speed_kmh_alias?(matched_key)
    numeric.round(1)
  end

  def accuracy(feature)
    find_field(feature[:properties], :accuracy)
  end
end
