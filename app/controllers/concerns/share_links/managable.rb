# frozen_string_literal: true

module ShareLinks
  module Managable
    extend ActiveSupport::Concern

    included do
      before_action :authenticate_user!
      before_action :prepare_share_context
    end

    def new
      @shared_link = SharedLink.new(build_attributes_for_new) unless @share
      render layout: false if turbo_frame_request?
    end

    def create
      revoke_existing_active_shares!

      @shared_link = current_user.shared_links.build(build_attributes_for_create)

      if @shared_link.save
        SharedLinks::OgImageJob.perform_later(@shared_link.id)
        redirect_to redirect_after_action_path, notice: 'Share link created.'
      else
        @share = nil
        render :new, status: :unprocessable_content, layout: !turbo_frame_request?
      end
    end

    def destroy
      return ensure_share! unless @share

      @share.destroy!
      redirect_to redirect_after_action_path, notice: 'Share link deleted.'
    end

    def revoke
      return ensure_share! unless @share

      @share.update!(revoked_at: Time.current)
      redirect_to redirect_after_action_path, notice: 'Share link revoked.'
    end

    def regenerate
      return ensure_share! unless @share

      transferred = nil
      current_user.shared_links.transaction do
        transferred = current_user.shared_links.create!(
          resource_type: @share.resource_type,
          resource_id:   @share.resource_id,
          name:          @share.name,
          magic_phrase:  @share.magic_phrase,
          settings:      @share.settings,
          expires_at:    @share.expires_at
        )
        @share.destroy!
      end
      SharedLinks::OgImageJob.perform_later(transferred.id)
      redirect_to redirect_after_action_path, notice: 'URL regenerated.'
    end

    def regenerate_phrase
      return ensure_share! unless @share

      @share.update!(magic_phrase: SharedLink::PhraseGenerator.call)
      redirect_to redirect_after_action_path, notice: 'Magic phrase regenerated.'
    end

    private

    def prepare_share_context
      load_share_dependencies if respond_to?(:load_share_dependencies, true)
      return if performed?

      load_active_share
    end

    def load_active_share
      @share = active_share_scope&.active&.first
    end

    def ensure_share!
      redirect_to fallback_path, alert: 'No active share link.'
    end

    def revoke_existing_active_shares!
      active_share_scope.active.update_all(revoked_at: Time.current)
    end

    def extracted_settings
      raw = params.fetch(:shared_link, {})[:settings]
      return {} if raw.blank?

      keys = %i[show_photos show_stats]
      permitted = raw.respond_to?(:permit) ? raw.permit(*keys) : raw.slice(*keys.map(&:to_s))
      permitted.to_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
    end
  end
end
