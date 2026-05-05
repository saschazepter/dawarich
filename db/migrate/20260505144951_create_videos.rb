# frozen_string_literal: true

class CreateVideos < ActiveRecord::Migration[8.0]
  def up
    unless table_exists?(:videos)
      create_table :videos do |t|
        t.references :user, null: false, foreign_key: true
        t.references :track, null: true, foreign_key: true
        t.datetime :start_at, null: false
        t.datetime :end_at, null: false
        t.integer :status, default: 0, null: false
        t.jsonb :config, default: {}, null: false
        t.string :error_message
        t.string :callback_nonce, null: false
        t.datetime :processing_started_at
        t.timestamps
      end
    end

    add_index :videos, :status unless index_name_exists?(:videos, :index_videos_on_status)

    return if index_name_exists?(:videos, :index_videos_on_user_id_and_status)

    add_index :videos, %i[user_id status]
  end

  def down
    drop_table :videos if table_exists?(:videos)
  end
end
