# frozen_string_literal: true

class BackfillUnsupportedExtractionStatus < ActiveRecord::Migration[8.0]
  ADAPTER_SUPPORTED_SOURCES = [
    0, # google_semantic_history
    2, # google_records
    3, # google_phone_takeout
    13 # polarsteps
  ].freeze

  UNSUPPORTED_STATUS = 5

  disable_ddl_transaction!

  def up
    Import.in_batches(of: 1000) do |batch|
      batch.where.not(source: ADAPTER_SUPPORTED_SOURCES)
           .update_all(additional_data_extraction_status: UNSUPPORTED_STATUS)
    end
  end

  def down
    Import.in_batches(of: 1000) do |batch|
      batch.where(additional_data_extraction_status: UNSUPPORTED_STATUS)
           .update_all(additional_data_extraction_status: 0)
    end
  end
end
