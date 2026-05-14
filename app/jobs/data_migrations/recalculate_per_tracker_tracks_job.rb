# frozen_string_literal: true

class DataMigrations::RecalculatePerTrackerTracksJob < ApplicationJob
  queue_as :data_migrations

  FLAG_KEY = 'per_tracker_recalculation_queued_at'

  def perform
    user_ids = User.where('EXISTS (SELECT 1 FROM tracks WHERE tracks.user_id = users.id)').pluck(:id)
    return if user_ids.empty?

    Rails.logger.info(
      "[DataMigrations::RecalculatePerTrackerTracks] enqueuing recalculation for #{user_ids.size} user(s)"
    )

    user_ids.each do |user_id|
      user = User.find_by(id: user_id)
      next unless user
      next if user.settings.is_a?(Hash) && user.settings[FLAG_KEY].present?

      Users::RecalculateDataJob.perform_later(user_id)

      user.settings = (user.settings || {}).merge(FLAG_KEY => Time.current.iso8601)
      user.save!(touch: false)
    end
  end
end
