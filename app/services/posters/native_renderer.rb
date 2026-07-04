# frozen_string_literal: true

require 'open3'

module Posters
  # Renders a poster in-process via the vendored maplibre-native Node
  # renderer (vendor/poster_renderer) — the same style and typography
  # modules the browser studio runs, fed by the existing vector tiles.
  # Seconds instead of the sidecar's minutes.
  class NativeRenderer
    class Error < StandardError; end

    # 3:4 print poster: 1200x1600 logical at ratio 2 = 2400x3200 px,
    # which is 203 dpi on the 300x400 mm print product.
    SIZE = { width: 1200, height: 1600, ratio: 2 }.freeze
    PRINT = { width_mm: 300, height_mm: 400, dpi: 203 }.freeze
    RENDER_TIMEOUT = 180

    def initialize(poster:, track:, distance:, route_opacity:, subtitle:, command: nil)
      @poster = poster
      @track = track
      @distance = distance
      @route_opacity = route_opacity
      @subtitle = subtitle
      @command = command || default_command
    end

    def call
      Dir.mktmpdir('poster_render') do |dir|
        job_path = File.join(dir, 'job.json')
        png_path = File.join(dir, 'poster.png')
        pdf_path = File.join(dir, 'poster.pdf')
        File.write(job_path, JSON.generate(job(png_path, pdf_path)))

        run_renderer(job_path)

        { png: File.binread(png_path), pdf: File.binread(pdf_path) }
      end
    end

    private

    def job(png_path, pdf_path)
      {
        tokens: theme_tokens,
        trackGeojson: { type: 'Feature', properties: {}, geometry: @track },
        trackOpacity: @route_opacity,
        view: {
          lat: @poster.settings['lat'].to_f,
          lon: @poster.settings['lon'].to_f,
          distance: @distance
        },
        size: SIZE,
        text: { title: poster_title, subtitle: @subtitle, coords: true },
        output: {
          png: png_path,
          pdf: pdf_path,
          widthMm: PRINT[:width_mm],
          heightMm: PRINT[:height_mm],
          dpi: PRINT[:dpi]
        }
      }
    end

    # The on-poster title is decoupled from the gallery name: an untitled
    # poster stores a blank settings['title'] and renders no title. Posters
    # saved before this split have no 'title' key and fall back to the name.
    def poster_title
      @poster.settings.fetch('title') { @poster.name }
    end

    def theme_tokens
      key = File.basename(@poster.settings.fetch('theme', 'terracotta').to_s)
      path = Rails.public_path.join('poster_themes', "#{key}.json")
      raise Error, "Unknown poster theme #{key.inspect}" unless path.exist?

      JSON.parse(path.read)
    end

    def run_renderer(job_path)
      stdout, stderr, status = Open3.capture3(*@command, job_path)
      return if status.success?

      raise Error, "Poster renderer failed (#{status.exitstatus}): #{stderr.presence || stdout}".strip
    end

    def default_command
      script = Rails.root.join('vendor/poster_renderer/render.sh').to_s
      ENV['POSTER_RENDERER_CMD'].presence&.split || [script]
    end
  end
end
