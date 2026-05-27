# frozen_string_literal: true

module Api
  module V1
    module Shared
      class PhotosController < BaseController
        def index
          return render(json: []) unless ctx.show_photos?

          photos = fetch_trip_photos
          render json: photos.map { |p| serialize(p) }
        rescue StandardError => e
          Rails.logger.error("Shared photos fetch failed: #{e.class} #{e.message}")
          render json: []
        end

        def thumbnail
          return head(:not_found) unless ctx.show_photos?

          upstream = Photos::Thumbnail.new(link.user, params[:source], params[:photo_id]).call
          return head(:not_found) unless upstream.success?

          send_data upstream.body, type: 'image/jpeg', disposition: 'inline'
        rescue StandardError => e
          Rails.logger.error("Shared thumbnail fetch failed: #{e.class} #{e.message}")
          head :not_found
        end

        private

        def fetch_trip_photos
          trip = link.resource
          return [] if trip.nil?

          Trips::Photos.new(trip, link.user).call
        end

        def serialize(photo)
          {
            id: photo[:id],
            latitude: photo[:latitude],
            longitude: photo[:longitude],
            source: photo[:source],
            thumbnail_url: url_for(
              controller: 'api/v1/shared/photos',
              action: 'thumbnail',
              id: link.id,
              photo_id: photo[:id],
              source: photo[:source],
              only_path: true
            )
          }
        end
      end
    end
  end
end
