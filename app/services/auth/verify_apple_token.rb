# frozen_string_literal: true

module Auth
  class VerifyAppleToken
    class InvalidToken < StandardError; end

    # apple_id is only loaded when an Apple token is actually verified.
    # The JWKS cache wiring lives here (not in an initializer) for the
    # same reason.
    def self.load_apple_id!
      return if @apple_id_loaded

      require 'apple_id'
      AppleID::JWKS.cache = Rails.cache
      @apple_id_loaded = true
    end

    def initialize(id_token, nonce: nil, client_id: nil)
      @id_token = id_token
      @nonce = nonce
      @client_id = client_id
    end

    def call
      # Must load before anything can raise: the rescue clause below names
      # AppleID/JSON::JWT constants, which only exist once the gem is loaded.
      self.class.load_apple_id!

      raise InvalidToken, 'blank token' if @id_token.blank?
      raise InvalidToken, 'client_id not configured' if effective_client_id.blank?

      decoded = AppleID::IdToken.decode(@id_token)
      verify_args = { client: effective_client_id }
      verify_args[:nonce] = expected_nonce_hash if @nonce.present?

      decoded.verify!(**verify_args)

      log_missing_nonce_breadcrumb if @nonce.blank?

      {
        sub: decoded.sub,
        email: decoded.email,
        email_verified: decoded.email_verified?,
        is_private_email: decoded.is_private_email?
      }
    rescue AppleID::IdToken::VerificationFailed, JSON::JWT::Exception => e
      raise InvalidToken, e.message
    end

    private

    def effective_client_id
      @client_id || ENV['APPLE_BUNDLE_ID']
    end

    def expected_nonce_hash
      Digest::SHA256.hexdigest(@nonce.to_s)
    end

    def log_missing_nonce_breadcrumb
      return unless defined?(Sentry)

      Sentry.capture_message(
        'apple_id_token_missing_nonce',
        level: :warning,
        extra: { hint: 'Hard-require nonce after mobile client rollout' }
      )
    rescue StandardError
      nil
    end
  end
end
