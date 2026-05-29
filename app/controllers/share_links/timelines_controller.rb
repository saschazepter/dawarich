# frozen_string_literal: true

module ShareLinks
  class TimelinesController < ApplicationController
    before_action :authenticate_user!
    before_action :load_active_share

    def new
      unless @share
        @shared_link = SharedLink.new(
          user: current_user,
          resource_type: :timeline,
          name: default_name_from_params,
          settings: SharedLink.default_settings_for(:timeline).merge(
            'start_date' => params[:start_date].presence,
            'end_date'   => params[:end_date].presence
          ).compact
        )
      end
      render layout: false if turbo_frame_request?
    end

    def create
      revoke_existing_active_shares!

      @shared_link = current_user.shared_links.build(
        resource_type: :timeline,
        resource_id:   nil,
        name:          create_params[:name].presence || default_name_for(create_params),
        magic_phrase:  create_params[:magic_phrase].presence,
        settings:      SharedLink.default_settings_for(:timeline).merge(
          'start_date' => create_params[:start_date],
          'end_date'   => create_params[:end_date]
        ).merge(extracted_settings)
      )

      if @shared_link.save
        SharedLinks::OgImageJob.perform_later(@shared_link.id)
        redirect_to new_share_links_timeline_path, notice: 'Share link created.'
      else
        @share = nil
        render :new, status: :unprocessable_content, layout: !turbo_frame_request?
      end
    end

    def destroy
      return ensure_share! unless @share

      @share.destroy!
      redirect_to new_share_links_timeline_path, notice: 'Share link deleted.'
    end

    def revoke
      return ensure_share! unless @share

      @share.update!(revoked_at: Time.current)
      redirect_to new_share_links_timeline_path, notice: 'Share link revoked.'
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
      redirect_to new_share_links_timeline_path, notice: 'URL regenerated.'
    end

    def regenerate_phrase
      return ensure_share! unless @share

      @share.update!(magic_phrase: SharedLink::PhraseGenerator.call)
      redirect_to new_share_links_timeline_path, notice: 'Magic phrase regenerated.'
    end

    private

    def load_active_share
      @share = current_user.shared_links.where(resource_type: :timeline).active.first
    end

    def ensure_share!
      redirect_to map_v2_path, alert: 'No active timeline share.'
    end

    def revoke_existing_active_shares!
      current_user.shared_links.where(resource_type: :timeline).active.update_all(revoked_at: Time.current)
    end

    def default_name_from_params
      return nil unless params[:start_date].present? && params[:end_date].present?

      "Timeline: #{params[:start_date]} → #{params[:end_date]}"
    end

    def default_name_for(attrs)
      "Timeline: #{attrs[:start_date]} → #{attrs[:end_date]}"
    end

    def create_params
      params.fetch(:shared_link, {}).permit(:name, :magic_phrase, :start_date, :end_date)
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
