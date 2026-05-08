# frozen_string_literal: true

class EnsureTrackerIdOnTracks < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:tracks, :tracker_id)

    add_column :tracks, :tracker_id, :string
  end

  def down
    # No-op: leave tracker_id in place. Removal is per-tracker plan's concern.
  end
end
