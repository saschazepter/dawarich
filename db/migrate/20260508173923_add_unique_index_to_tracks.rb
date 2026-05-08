# frozen_string_literal: true

class AddUniqueIndexToTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # If a previous run failed mid-build, Postgres leaves an INVALID index
    # behind that blocks recreation. Drop it first so re-running the
    # migration is safe.
    execute 'DROP INDEX IF EXISTS index_tracks_on_user_start_end_unique'

    add_index :tracks,
              %i[user_id start_at end_at],
              unique: true,
              algorithm: :concurrently,
              name: 'index_tracks_on_user_start_end_unique'
  end

  def down
    remove_index :tracks,
                 name: 'index_tracks_on_user_start_end_unique',
                 algorithm: :concurrently
  end
end
