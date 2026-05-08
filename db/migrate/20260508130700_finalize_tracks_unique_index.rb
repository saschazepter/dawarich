# frozen_string_literal: true

class FinalizeTracksUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'idx_tracks_user_tracker_start_at_unique'
  LEGACY_INDEX_NAME = 'idx_tracks_user_tracker_end_at'

  def up
    return unless column_exists?(:tracks, :tracker_id)
    return if index_name_exists?(:tracks, INDEX_NAME)

    if index_name_exists?(:tracks, LEGACY_INDEX_NAME)
      remove_index :tracks, name: LEGACY_INDEX_NAME, algorithm: :concurrently
    end

    add_index :tracks, %i[user_id tracker_id start_at],
              unique: true,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:tracks, INDEX_NAME)

    remove_index :tracks, name: INDEX_NAME, algorithm: :concurrently
  end
end
