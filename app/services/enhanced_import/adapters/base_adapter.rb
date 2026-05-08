# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class BaseAdapter
      include Imports::FileLoader

      attr_reader :import, :file_path

      def initialize(import, file_path = nil)
        @import = import
        @file_path = file_path
      end

      def translate(&)
        raise NotImplementedError
      end

      protected

      # Large exports must never be read into memory whole; hand the caller an
      # IO over a local copy and clean the copy up afterwards.
      def stream_file(&block)
        path = resolve_file_path
        File.open(path, 'rb', &block)
      ensure
        cleanup_temp_file
      end

      def parse_lat_lng(latlng_string)
        return nil if latlng_string.blank?

        cleaned = latlng_string.to_s.gsub('°', '').gsub('°', '').strip
        parts = cleaned.split(/,\s*/)
        return nil if parts.size < 2

        [parts[0].to_f, parts[1].to_f]
      end

      def parse_e7(value)
        return nil if value.nil?

        value.to_f / 10**7
      end
    end
  end
end
