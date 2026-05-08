# frozen_string_literal: true

class AddTrackerIdToTracks < ActiveRecord::Migration[8.0]
  def change
    add_column :tracks, :tracker_id, :string
  end
end
