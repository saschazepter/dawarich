# frozen_string_literal: true

require 'nokogiri'

class Places::GpxWaypointImporter
  include Imports::FileLoader

  BATCH_SIZE = 500
  DEFAULT_NAME = 'Imported waypoint'

  attr_reader :import, :user_id, :file_path, :imported_count

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
    @imported_count = 0
  end

  def call
    batch = []
    each_wpt do |wpt|
      row = prepare_place(wpt)
      next unless row

      batch << row
      next if batch.size < BATCH_SIZE

      flush(batch)
      batch = []
    end
    flush(batch) unless batch.empty?
    imported_count
  end

  private

  def each_wpt(&block)
    path = resolve_file_path
    File.open(path, 'rb') do |io|
      prefix = io.read(256) || ''
      io.seek(prefix.index('<') || 0)
      handler = WptStreamHandler.new(&block)
      Nokogiri::XML::SAX::Parser.new(handler).parse(io)
    end
  end

  def prepare_place(wpt)
    lat = wpt['lat']
    lon = wpt['lon']
    return if lat.blank? || lon.blank?

    name = wpt['name'].to_s.strip
    name = DEFAULT_NAME if name.blank?

    longitude = lon.to_f.round(6)
    latitude  = lat.to_f.round(6)

    {
      name: name,
      latitude: latitude,
      longitude: longitude,
      lonlat: "POINT(#{longitude} #{latitude})",
      source: Place.sources[:gpx_waypoint],
      user_id: user_id,
      geodata: {},
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def flush(batch)
    return if batch.empty?

    result = Place.insert_all(batch)
    @imported_count += result.length
  end

  class WptStreamHandler < Nokogiri::XML::SAX::Document
    CAPTURED_CHILDREN = %w[name ele time cmt desc].freeze

    def initialize(&block)
      super()
      @callback = block
      @current = nil
      @capturing_child = nil
      @text = +''
    end

    def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
      if name == 'wpt'
        @current = attrs.each_with_object({}) { |a, h| h[a.localname] = a.value }
        @capturing_child = nil
        @text = +''
        return
      end

      return unless @current
      return unless CAPTURED_CHILDREN.include?(name)

      @capturing_child = name
      @text = +''
    end

    def characters(string)
      @text << string if @capturing_child
    end

    def end_element_namespace(name, _prefix = nil, _uri = nil)
      if name == 'wpt' && @current
        @callback.call(@current)
        @current = nil
        @capturing_child = nil
        @text = +''
        return
      end

      return unless @capturing_child && name == @capturing_child

      @current[@capturing_child] = @text.strip if @current
      @capturing_child = nil
      @text = +''
    end

    def error(message)
      raise Nokogiri::XML::SyntaxError, "GPX parse error: #{message}"
    end
  end
end
