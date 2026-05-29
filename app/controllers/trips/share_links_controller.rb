# frozen_string_literal: true

module Trips
  class ShareLinksController < ApplicationController
    before_action :authenticate_user!
    before_action :load_trip
    before_action :load_active_share

    def new
      unless @share
        @shared_link = SharedLink.new(
          user: current_user,
          resource_type: :trip,
          resource_id: @trip.id,
          name: "Trip: #{@trip.name}"
        )
      end
      render layout: false if turbo_frame_request?
    end

    def create
      revoke_existing_active_shares!

      name = create_params[:name].presence || "Trip: #{@trip.name}"
      @shared_link = current_user.shared_links.build(
        resource_type: :trip,
        resource_id:   @trip.id,
        name:          name,
        magic_phrase:  create_params[:magic_phrase].presence,
        expires_at:    create_params[:expires_at].presence,
        settings:      default_settings.merge(extracted_settings)
      )

      if @shared_link.save
        SharedLinks::OgImageJob.perform_later(@shared_link.id)
        redirect_to new_trip_share_link_path(@trip), notice: 'Share link created.'
      else
        @share = nil
        render :new, status: :unprocessable_content, layout: !turbo_frame_request?
      end
    end

    def destroy
      return ensure_share! unless @share

      @share.destroy!
      redirect_to new_trip_share_link_path(@trip), notice: 'Share link deleted.'
    end

    def revoke
      return ensure_share! unless @share

      @share.update!(revoked_at: Time.current)
      redirect_to new_trip_share_link_path(@trip), notice: 'Share link revoked.'
    end

    def regenerate
      return ensure_share! unless @share

      transferred = current_user.shared_links.create!(
        resource_type: @share.resource_type,
        resource_id:   @share.resource_id,
        name:          @share.name,
        magic_phrase:  @share.magic_phrase,
        settings:      @share.settings,
        expires_at:    @share.expires_at
      )
      @share.destroy!
      SharedLinks::OgImageJob.perform_later(transferred.id)
      redirect_to new_trip_share_link_path(@trip), notice: 'URL regenerated.'
    end

    def regenerate_phrase
      return ensure_share! unless @share

      @share.update!(magic_phrase: SharedLink::PhraseGenerator.call)
      redirect_to new_trip_share_link_path(@trip), notice: 'Magic phrase regenerated.'
    end

    private

    def load_trip
      @trip = current_user.trips.find_by(id: params[:trip_id])
      return if @trip

      render plain: 'Not found', status: :not_found
    end

    def load_active_share
      @share = @trip&.shared_links&.active&.first
    end

    def ensure_share!
      redirect_to trip_path(@trip), alert: 'No active share link.'
    end

    def revoke_existing_active_shares!
      @trip.shared_links.active.update_all(revoked_at: Time.current)
    end

    def default_settings
      SharedLink.default_settings_for(:trip)
    end

    def create_params
      params.fetch(:shared_link, {}).permit(:name, :magic_phrase, :expires_at)
    end

    def extracted_settings
      raw = params.fetch(:shared_link, {})[:settings]
      return {} if raw.blank?

      keys = %i[show_photos show_places show_addresses show_stats]
      permitted = raw.respond_to?(:permit) ? raw.permit(*keys) : raw.slice(*keys.map(&:to_s))
      permitted.to_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
    end
  end
end
