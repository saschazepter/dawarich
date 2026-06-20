# frozen_string_literal: true

module Api
  module V1
    module Shared
      class BaseController < ApplicationController
        skip_before_action :verify_authenticity_token, raise: false
        before_action :load_link
        before_action :verify_phrase

        protected

        attr_reader :link

        def ctx
          @ctx ||= SharedLinkContext.new(@link)
        end

        private

        def load_link
          @link = SharedLink.active.find_by(id: params[:id])
          return if @link

          render json: { error: 'not_found' }, status: :not_found
        end

        def verify_phrase
          return if @link.nil?
          return if @link.magic_phrase.blank?
          return if cookies.encrypted["shared_link_#{@link.id}"] == @link.unlock_token

          render json: { error: 'unauthorized' }, status: :unauthorized
        end

        def cache_public_for(seconds)
          return if link&.magic_phrase.present?

          expires_in seconds, public: true
        end

        def privacy_zones
          @privacy_zones ||= link.user.tags.privacy_zones.includes(:places).flat_map do |tag|
            tag.places.map do |place|
              { lon: place.longitude.to_f, lat: place.latitude.to_f, radius: tag.privacy_radius_meters }
            end
          end
        end

        def within_privacy_zone?(lat, lon)
          return false if lat.blank? || lon.blank?

          privacy_zones.any? do |zone|
            haversine_meters(lat.to_f, lon.to_f, zone[:lat], zone[:lon]) <= zone[:radius]
          end
        end

        def haversine_meters(lat1, lon1, lat2, lon2)
          rad = Math::PI / 180
          dlat = (lat2 - lat1) * rad
          dlon = (lon2 - lon1) * rad
          a = (Math.sin(dlat / 2)**2) +
              (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlon / 2)**2))
          6_371_000 * 2 * Math.asin(Math.sqrt(a))
        end
      end
    end
  end
end
