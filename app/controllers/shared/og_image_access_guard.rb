# frozen_string_literal: true

module Shared
  class OgImageAccessGuard
    def self.allowed?(request)
      token = ENV['OG_RENDER_TOKEN']
      return false if token.blank?

      ActiveSupport::SecurityUtils.secure_compare(token, request.headers['X-OG-Render-Token'].to_s)
    end
  end
end
