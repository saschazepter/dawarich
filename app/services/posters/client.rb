# frozen_string_literal: true

module Posters
  class Client
    class Error < StandardError; end

    START_TIMEOUT = 15
    STATUS_TIMEOUT = 10
    RESULT_TIMEOUT = 30
    THEMES_TIMEOUT = 10

    def start_render(payload)
      response = HTTParty.post(
        "#{base_url}/jobs",
        headers: headers.merge('Content-Type' => 'application/json'),
        body: payload.to_json,
        timeout: START_TIMEOUT
      )
      raise Error, "poster service responded with #{response.code}" unless response.success?

      response.parsed_response['job_id']
    end

    def job_status(job_id)
      response = HTTParty.get(
        "#{base_url}/jobs/#{job_id}",
        headers: headers,
        timeout: STATUS_TIMEOUT
      )
      raise Error, "poster service responded with #{response.code}" unless response.success?

      response.parsed_response
    end

    def job_result(job_id)
      response = HTTParty.get(
        "#{base_url}/jobs/#{job_id}/result",
        headers: headers,
        timeout: RESULT_TIMEOUT
      )
      raise Error, "poster service responded with #{response.code}" unless response.success?

      response.body
    end

    def themes
      response = HTTParty.get("#{base_url}/themes", headers: headers, timeout: THEMES_TIMEOUT)
      return [] unless response.success?

      JSON.parse(response.body)
    rescue HTTParty::Error, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError
      []
    end

    private

    def base_url
      POSTER_SERVICE_URL.to_s.chomp('/')
    end

    def headers
      POSTER_SERVICE_TOKEN.present? ? { 'X-Poster-Token' => POSTER_SERVICE_TOKEN } : {}
    end
  end
end
