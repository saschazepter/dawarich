# frozen_string_literal: true

require 'nokogiri'

class Gpx::TrackImporter
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    batch = []
    each_trkpt do |point_hash|
      data = prepare_point(point_hash)
      next unless data

      batch << data
      next if batch.size < BATCH_SIZE

      flush(batch)
      batch = []
    end
    flush(batch) unless batch.empty?
  ensure
    cleanup_temp_file
  end

  private

  def each_trkpt(&block)
    path = resolve_file_path
    File.open(path, 'rb') do |io|
      seek_to_document_start(io)
      handler = TrkptStreamHandler.new(&block)
      Nokogiri::XML::SAX::Parser.new(handler).parse(io)
    end
  end

  def seek_to_document_start(io)
    prefix = io.read(256) || ''
    io.seek(prefix.index('<') || 0)
  end

  def flush(batch)
    inserted = bulk_insert_points(batch)
    broadcast_import_progress(import, inserted)
  end

  def prepare_point(point)
    return if point['lat'].blank? || point['lon'].blank? || point['time'].blank?

    elevation = point['ele'].to_f

    {
      lonlat: "POINT(#{point['lon'].to_d} #{point['lat'].to_d})",
      # During the integer→decimal altitude migration we write to both
      # columns; readers (`Point#altitude`) prefer altitude_decimal.
      altitude: elevation,
      altitude_decimal: elevation,
      timestamp: Time.zone.parse(point['time']).utc.to_i,
      import_id: import.id,
      velocity: speed(point),
      raw_data: point,
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def importer_name
    'GPX'
  end

  def speed(point)
    return if point['extensions'].blank?

    value = point.dig('extensions', 'speed')
    extensions = point.dig('extensions', 'TrackPointExtension')
    value ||= extensions.is_a?(Hash) ? extensions['speed'] : nil

    value&.to_f&.round(1)
  end

  class TrkptStreamHandler < Nokogiri::XML::SAX::Document
    def initialize(&block)
      super()
      @callback = block
      @stack = nil
      @text = +''
    end

    def start_element_namespace(name, attrs = [], _prefix = nil, _uri = nil, _namespaces = [])
      attrs_h = attrs.each_with_object({}) { |a, h| h[a.localname] = a.value }
      if name == 'trkpt' && @stack.nil?
        @stack = [attrs_h]
        @text = +''
      elsif @stack
        @stack.last[name] = attrs_h
        @stack.push(attrs_h)
        @text = +''
      end
    end

    def characters(string)
      @text << string if @stack
    end

    def end_element_namespace(name, _prefix = nil, _uri = nil)
      return unless @stack

      closed = @stack.pop
      if @stack.empty?
        @callback.call(closed)
        @stack = nil
      else
        @stack.last[name] = @text.strip if closed.empty?
        @text = +''
      end
    end
  end
end
