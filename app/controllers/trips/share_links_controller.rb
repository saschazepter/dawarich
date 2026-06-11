# frozen_string_literal: true

module Trips
  class ShareLinksController < ApplicationController
    include ShareLinks::Managable

    private

    def load_share_dependencies
      @trip = current_user.trips.find_by(id: params[:trip_id])
      return if @trip

      render plain: 'Not found', status: :not_found
    end

    def active_share_scope
      @trip&.shared_links&.where(resource_type: :trip)
    end

    def redirect_after_action_path
      new_trip_share_link_path(@trip)
    end

    def fallback_path
      trip_path(@trip)
    end

    def build_attributes_for_new
      {
        user: current_user,
        resource_type: :trip,
        resource_id: @trip.id,
        name: "Trip: #{@trip.name}"
      }
    end

    def build_attributes_for_create
      {
        resource_type: :trip,
        resource_id:   @trip.id,
        name:          create_params[:name].presence || "Trip: #{@trip.name}",
        magic_phrase:  create_params[:magic_phrase].presence,
        expires_at:    create_params[:expires_at].presence,
        settings:      SharedLink.default_settings_for(:trip).merge(extracted_settings)
      }
    end

    def create_params
      params.fetch(:shared_link, {}).permit(:name, :magic_phrase, :expires_at)
    end
  end
end
