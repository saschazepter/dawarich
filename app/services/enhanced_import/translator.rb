# frozen_string_literal: true

module EnhancedImport
  class Translator
    SUPPORTED_SOURCES = %w[
      google_records
      google_phone_takeout
      google_semantic_history
      polarsteps
    ].freeze

    ADAPTER_LOOKUP = {
      'google_records' => 'EnhancedImport::Adapters::GoogleRecordsAdapter',
      'google_phone_takeout' => 'EnhancedImport::Adapters::GooglePhoneTakeoutAdapter',
      'google_semantic_history' => 'EnhancedImport::Adapters::GoogleSemanticHistoryAdapter',
      'polarsteps' => 'EnhancedImport::Adapters::PolarstepsAdapter'
    }.freeze

    def self.supported?(source)
      SUPPORTED_SOURCES.include?(source.to_s)
    end

    def initialize(import)
      @import = import
    end

    def translate(&block)
      return enum_for(:translate) unless block_given?

      adapter = adapter_for(@import.source)
      return if adapter.nil?

      adapter.new(@import).translate(&block)
    end

    private

    def adapter_for(source)
      class_name = ADAPTER_LOOKUP[source.to_s]
      return nil if class_name.nil?

      class_name.safe_constantize
    end
  end
end
