# frozen_string_literal: true

module Videos
  class RequestRender
    class RenderError < StandardError; end

    MAX_COORDINATES = 50_000
    DEFAULT_CONFIG = { map_behavior: 'fit_full_route' }.freeze

    def initialize(video:)
      @video = video
    end

    def call
      payload = render_payload
      raise RenderError, 'No coordinates found for the given date range' if payload[:coordinates].empty?

      response = post_render_request(payload)
      handle_response(response)
    end

    private

    attr_reader :video

    def post_render_request(payload)
      uri = URI.parse("#{service_url.chomp('/')}/api/render")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 30

      headers = { 'Content-Type' => 'application/json' }
      token = ENV['VIDEO_SERVICE_AUTH_TOKEN']
      headers['Authorization'] = "Bearer #{token}" if token.present?

      request = Net::HTTP::Post.new(uri.path, headers)
      request.body = payload.to_json
      http.request(request)
    end

    def handle_response(response)
      return if response.is_a?(Net::HTTPSuccess)

      body = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        {}
      end
      raise RenderError, "Video service returned #{response.code}: #{body['error'] || response.message}"
    end

    def render_payload
      urls = callback_urls
      {
        video_id: video.id,
        callback_url: urls.first,
        callback_urls: urls,
        config: DEFAULT_CONFIG,
        coordinates: track_coordinates
      }
    end

    def track_coordinates
      points = video.track_id.present? ? track_points : range_points
      coords = points.pluck(
        Arel.sql('COALESCE(longitude, ST_X(lonlat::geometry))'),
        Arel.sql('COALESCE(latitude, ST_Y(lonlat::geometry))'),
        :timestamp
      ).filter_map { |lon, lat, ts| [lon.to_f, lat.to_f, ts] if lon && lat }

      downsample(coords)
    end

    def track_points
      points = video.track.points.order(:timestamp)
      return points.limit(MAX_COORDINATES * 2) if points.exists?

      video.user.points
           .where(timestamp: video.track.start_at.to_i..video.track.end_at.to_i)
           .order(:timestamp)
           .limit(MAX_COORDINATES * 2)
    end

    def range_points
      video.user.points
           .where(timestamp: video.start_at.to_i..video.end_at.to_i)
           .order(:timestamp)
           .limit(MAX_COORDINATES * 2)
    end

    def downsample(coords)
      return coords if coords.length <= MAX_COORDINATES

      step = (coords.length - 1).to_f / (MAX_COORDINATES - 1)
      result = Array.new(MAX_COORDINATES) { |i| coords[(i * step).round] }
      result[0] = coords.first
      result[-1] = coords.last
      result
    end

    def callback_urls
      token = Videos::CallbackToken.generate(video.id, video.callback_nonce)
      callback_path = "/api/v1/videos/#{video.id}/callback?token=#{token}"
      protocol = ENV.fetch('APPLICATION_PROTOCOL', 'http')

      hosts = ENV.fetch('APPLICATION_HOSTS', 'localhost')
                 .split(',').map(&:strip).reject(&:blank?)
      hosts.map { |host| "#{protocol}://#{host}#{callback_path}" }
    end

    def service_url
      ENV.fetch('VIDEO_SERVICE_URL')
    end
  end
end
