# frozen_string_literal: true

module AirTrail
  class ConnectionTester
    def initialize(url, api_key, skip_ssl_verification: false)
      @url = url
      @api_key = api_key
      @skip_ssl_verification = skip_ssl_verification
    end

    def call
      return { success: false, error: 'AirTrail URL is missing' } if @url.blank?
      return { success: false, error: 'AirTrail API key is missing' } if @api_key.blank?

      AirTrail::Client.new(@url, @api_key, skip_ssl_verification: @skip_ssl_verification).flights
      { success: true, message: 'AirTrail connection verified' }
    rescue AirTrail::Client::Error => e
      { success: false, error: "AirTrail connection failed: #{e.message}" }
    end
  end
end
