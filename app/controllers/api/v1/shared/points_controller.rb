# frozen_string_literal: true

module Api
  module V1
    module Shared
      class PointsController < BaseController
        def index
          render json: serialize(scoped_points)
        end

        private

        def scoped_points
          case link.resource_type.to_sym
          when :trip
            trip = link.resource
            return [] if trip.nil?

            trip.points
          when :timeline
            range = timeline_epoch_range
            return [] if range.nil?

            link.user.points.not_anomaly.where(timestamp: range).order(:timestamp)
          else
            []
          end
        end

        def timeline_epoch_range
          start_parsed = Time.find_zone('UTC').parse(link.settings['start_date'].to_s)
          end_parsed   = Time.find_zone('UTC').parse(link.settings['end_date'].to_s)
          return nil if start_parsed.nil? || end_parsed.nil?

          start_parsed.beginning_of_day.to_i..end_parsed.end_of_day.to_i
        rescue ArgumentError, TypeError
          nil
        end

        def serialize(points)
          return [] if points.respond_to?(:empty?) && points.empty?

          points.pluck(
            Arel.sql('ST_X(lonlat::geometry)'),
            Arel.sql('ST_Y(lonlat::geometry)'),
            :timestamp
          ).map { |lon, lat, ts| [lon, lat, ts.to_i] }
        end
      end
    end
  end
end
