# frozen_string_literal: true

module Videos
  class CallbackToken
    def self.generate(video_id, nonce)
      digest = OpenSSL::HMAC.digest('SHA256', secret, "#{video_id}:#{nonce}")
      Base64.urlsafe_encode64(digest, padding: false)
    end

    def self.verify(token, video_id, nonce)
      return false if token.blank?

      expected = generate(video_id, nonce)
      ActiveSupport::SecurityUtils.secure_compare(token, expected)
    rescue ArgumentError
      false
    end

    def self.secret
      Rails.application.secret_key_base
    end
    private_class_method :secret
  end
end
