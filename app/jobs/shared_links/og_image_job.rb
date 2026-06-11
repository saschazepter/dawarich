# frozen_string_literal: true

module SharedLinks
  class OgImageJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(link_id)
      link = SharedLink.find_by(id: link_id)
      return if link.nil?

      if ENV['OG_RENDER_TOKEN'].blank?
        link.update!(og_image_state: :failed)
        return
      end

      bytes = OgImageRenderer.new(link).call
      link.og_image.attach(
        io: StringIO.new(bytes),
        filename: "og-#{link.id}.png",
        content_type: 'image/png'
      )
      link.update!(og_image_state: :ready)
    rescue StandardError
      link&.update!(og_image_state: :failed)
      raise
    end
  end
end
