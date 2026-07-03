# frozen_string_literal: true

module Posters
  class Generate
    MAX_DISTANCE = 20_000
    MIN_DISTANCE = 500
    METERS_PER_DEGREE = 111_320.0
    POLL_INTERVAL = 2
    MAX_POLLS = 450

    def initialize(poster)
      @poster = poster
    end

    def call
      return if @poster.completed?

      @poster.update!(status: :processing)

      track = build_track
      return fail_with('No location data found for the selected period.') if track.nil?

      unless track_intersects_area?(track)
        return fail_with('Your track does not pass through the selected map area. ' \
                         'Recenter the map or adjust the dates.')
      end

      if DawarichSettings.poster_native_render_enabled?
        render_natively(track)
      else
        client = Posters::Client.new
        attach_image(render_format(client, track, 'png'))
        attach_print_pdf(render_format(client, track, 'pdf'))
      end
      @poster.update!(status: :completed)
    rescue StandardError => e
      ExceptionReporter.call(e, "Poster render failed for poster #{@poster.id}")
      fail_with('Poster service is unavailable. Please try again later.')
    end

    private

    def build_track
      builder_class = @poster.settings['source'] == 'tracks' ? Posters::TracksBuilder : Posters::TrackBuilder

      builder_class.new(
        user: @poster.user,
        start_at: Time.zone.parse(@poster.settings['start_at']),
        end_at: Time.zone.parse(@poster.settings['end_at'])
      ).call
    end

    def render_natively(track)
      record_progress('drawing_map')
      result = Posters::NativeRenderer.new(
        poster: @poster,
        track: track,
        distance: distance,
        route_opacity: route_opacity,
        subtitle: subtitle
      ).call
      attach_image(result[:png])
      attach_print_pdf(result[:pdf])
    end

    def render_format(client, track, format)
      job_id = client.start_render(render_payload(track, format))
      await_render(client, job_id)
    end

    def render_payload(track, format)
      settings = @poster.settings
      {
        lat: settings['lat'].to_f,
        lon: settings['lon'].to_f,
        distance: distance,
        theme: settings.fetch('theme', 'terracotta'),
        title: @poster.name,
        subtitle: subtitle,
        format: format,
        route_geojson: track,
        route_fill: route_fill?,
        route_opacity: route_opacity
      }
    end

    def route_fill?
      ActiveModel::Type::Boolean.new.cast(@poster.settings['route_fill']) || false
    end

    def route_opacity
      raw = @poster.settings['route_opacity'].to_f
      raw /= 100.0 if raw > 1
      raw = 0.6 if raw <= 0
      raw.clamp(0.05, 1.0)
    end

    def distance
      @poster.settings.fetch('distance', 6000).to_i.clamp(MIN_DISTANCE, MAX_DISTANCE)
    end

    def track_intersects_area?(track)
      lat = @poster.settings['lat'].to_f
      lon = @poster.settings['lon'].to_f
      lat_delta = (distance / 3.0) / METERS_PER_DEGREE
      lon_delta = (distance / 4.0) / (METERS_PER_DEGREE * Math.cos(lat * Math::PI / 180).abs.clamp(0.01, 1.0))

      track['coordinates'].any? do |segment|
        segment.any? do |pt_lon, pt_lat|
          pt_lat.between?(lat - lat_delta, lat + lat_delta) &&
            pt_lon.between?(lon - lon_delta, lon + lon_delta)
        end
      end
    end

    def subtitle
      start_at = Time.zone.parse(@poster.settings['start_at']).utc
      end_at = Time.zone.parse(@poster.settings['end_at']).utc

      "#{start_at.strftime('%-d %b %Y')} – #{end_at.strftime('%-d %b %Y')}"
    end

    def attach_image(image)
      @poster.image.attach(
        io: StringIO.new(image),
        filename: "poster_#{@poster.id}.png",
        content_type: 'image/png'
      )
    end

    def attach_print_pdf(pdf)
      @poster.print_pdf.attach(
        io: StringIO.new(pdf),
        filename: "poster_#{@poster.id}.pdf",
        content_type: 'application/pdf'
      )
    end

    def fail_with(message)
      @poster.update!(status: :failed, settings: @poster.settings.merge('error' => message))
    end

    def await_render(client, job_id)
      MAX_POLLS.times do
        status = client.job_status(job_id)

        case status['status']
        when 'done' then return client.job_result(job_id)
        when 'failed' then raise Posters::Client::Error, status['error'].to_s
        end

        record_progress(status['phase'])
        sleep(POLL_INTERVAL)
      end

      raise Posters::Client::Error, 'render timed out'
    end

    def record_progress(phase)
      return if phase.blank? || @poster.settings['progress_phase'] == phase

      @poster.update!(settings: @poster.settings.merge('progress_phase' => phase))
    end
  end
end
