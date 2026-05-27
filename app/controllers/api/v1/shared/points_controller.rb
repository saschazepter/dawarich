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
          else
            []
          end
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
