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
      end
    end
  end
end
