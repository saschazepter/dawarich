# frozen_string_literal: true

class ReplaceTracksUniqueIndexWithTrackerScoped < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  OLD_INDEX = 'index_tracks_on_user_start_end_unique'
  NEW_INDEX = 'index_tracks_on_user_tracker_start_end_unique'
  MIN_PG_VERSION = 150_000

  def up
    ensure_postgres_15_or_newer!

    unless index_name_exists?(:tracks, NEW_INDEX)
      add_index :tracks, %i[user_id tracker_id start_at end_at],
                unique: true,
                nulls_not_distinct: true,
                algorithm: :concurrently,
                name: NEW_INDEX
    end

    return unless index_name_exists?(:tracks, OLD_INDEX)

    remove_index :tracks, name: OLD_INDEX, algorithm: :concurrently
  end

  def down
    unless index_name_exists?(:tracks, OLD_INDEX)
      add_index :tracks, %i[user_id start_at end_at],
                unique: true,
                algorithm: :concurrently,
                name: OLD_INDEX
    end

    return unless index_name_exists?(:tracks, NEW_INDEX)

    remove_index :tracks, name: NEW_INDEX, algorithm: :concurrently
  end

  private

  def ensure_postgres_15_or_newer!
    server_version = ActiveRecord::Base.connection.select_value('SHOW server_version_num').to_i
    return if server_version >= MIN_PG_VERSION

    raise(
      "ReplaceTracksUniqueIndexWithTrackerScoped requires PostgreSQL 15 or newer " \
      "(detected server_version_num=#{server_version}). " \
      'NULLS NOT DISTINCT was introduced in PostgreSQL 15; upgrade your database before applying this migration.'
    )
  end
end
