# frozen_string_literal: true

class EnqueuePerTrackerTrackRecalculation < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::RecalculatePerTrackerTracksJob.perform_later
  end

  def down
    # Enqueued recalculation cannot be reversed.
  end
end
