# frozen_string_literal: true

class AddUniqueIndexToTrackSegments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_track_segments_track_start_index_unique'

  def up
    return if index_name_exists?(:track_segments, INDEX_NAME)

    add_index :track_segments, %i[track_id start_index],
              unique: true,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:track_segments, INDEX_NAME)

    remove_index :track_segments, name: INDEX_NAME, algorithm: :concurrently
  end
end
