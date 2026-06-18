# frozen_string_literal: true

module Api
  module V1
    module Shared
      class PointsController < BaseController
        MAX_POINTS = 10_000

        def index
          render json: serialize(scoped_points)
        end

        private

        def scoped_points
          case link.resource_type.to_sym
          when :trip
            trip = link.resource
            return [] if trip.nil?

            outside_privacy_zones(trip.points)
          when :timeline
            range = timeline_epoch_range
            return [] if range.nil?

            outside_privacy_zones(link.user.points.not_anomaly.where(timestamp: range).order(:timestamp))
          else
            []
          end
        end

        def outside_privacy_zones(points)
          zones = privacy_zones
          return points if zones.empty?

          condition = zones.map { 'ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)' }
                           .join(' OR ')
          points.where.not(condition, *zones.flat_map { |z| [z[:lon], z[:lat], z[:radius]] })
        end

        def privacy_zones
          link.user.tags.privacy_zones.includes(:places).flat_map do |tag|
            tag.places.map do |place|
              { lon: place.longitude.to_f, lat: place.latitude.to_f, radius: tag.privacy_radius_meters }
            end
          end
        end

        def timeline_epoch_range
          zone = Time.find_zone(link.user.timezone_iana) || Time.find_zone('UTC')
          start_parsed = zone.parse(link.settings['start_date'].to_s)
          end_parsed   = zone.parse(link.settings['end_date'].to_s)
          return nil if start_parsed.nil? || end_parsed.nil?

          start_parsed.beginning_of_day.to_i..end_parsed.end_of_day.to_i
        rescue ArgumentError, TypeError
          nil
        end

        def serialize(points)
          return [] unless points.respond_to?(:count)

          total = points.count
          return [] if total.zero?

          step = total > MAX_POINTS ? (total.to_f / MAX_POINTS).ceil : 1
          sampled_rows(points, step).map { |lon, lat, ts| [lon.to_f, lat.to_f, ts.to_i] }
        end

        def sampled_rows(relation, step)
          if step <= 1
            return relation.pluck(
              Arel.sql('ST_X(lonlat::geometry)'),
              Arel.sql('ST_Y(lonlat::geometry)'),
              :timestamp
            )
          end

          numbered = relation.select(
            Arel.sql('ST_X(lonlat::geometry) AS lon'),
            Arel.sql('ST_Y(lonlat::geometry) AS lat'),
            Arel.sql('timestamp'),
            Arel.sql('ROW_NUMBER() OVER (ORDER BY timestamp) AS rn')
          )
          sql = "SELECT lon, lat, timestamp FROM (#{numbered.to_sql}) sampled " \
                "WHERE (rn - 1) % #{step.to_i} = 0 ORDER BY timestamp"
          relation.klass.connection.select_rows(sql)
        end
      end
    end
  end
end
