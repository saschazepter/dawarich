# frozen_string_literal: true

class BackfillPointsToponyms < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::StartBackfillPointsToponymsJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue StartBackfillPointsToponymsJob: #{e.message}"
  end

  def down
    # no-op: toponym columns were repopulated asynchronously and are not reverted
  end
end
