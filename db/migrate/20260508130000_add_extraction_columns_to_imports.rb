# frozen_string_literal: true

class AddExtractionColumnsToImports < ActiveRecord::Migration[8.0]
  def change
    add_column :imports, :additional_data_extraction_status, :integer, default: 0, null: false
    add_column :imports, :additional_data_extraction, :jsonb, default: {}, null: false
    add_index :imports, :additional_data_extraction_status,
              name: 'index_imports_on_additional_data_extraction_status'
  end
end
