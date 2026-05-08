# frozen_string_literal: true

class AddUniqueIndexToTracks < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    execute "SET lock_timeout = '5s'"
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
