# frozen_string_literal: true

module Visits
  module DetectionHelpers
    DEFAULT_ACCURACY_METERS = 50

    private

    def calculate_weighted_center(points)
      point_array = Array(points)
      return [0.0, 0.0] if point_array.empty?

      total_weight = 0.0
      weighted_lat = 0.0
      weighted_lon = 0.0

      point_array.each do |point|
        accuracy = point.accuracy || DEFAULT_ACCURACY_METERS
        weight = 1.0 / [accuracy, 1].max

        weighted_lat += point.lat * weight
        weighted_lon += point.lon * weight
        total_weight += weight
      end

      [weighted_lat / total_weight, weighted_lon / total_weight]
    end

    def calculate_visit_radius(points, center)
      point_array = Array(points)
      return 15 if point_array.empty?

      max_distance_m = point_array.map do |point|
        Geocoder::Calculations.distance_between(center, [point.lat, point.lon], units: :km)
      end.max * 1000

      [max_distance_m, 15].max
    end

    def suggest_place_name(points)
      Visits::Names::Suggester.new(points).call
    end

    def fetch_place_name(center)
      Visits::Names::Fetcher.new(center).call
    end
  end
end
