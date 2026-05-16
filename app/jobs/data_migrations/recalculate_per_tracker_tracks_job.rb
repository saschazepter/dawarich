# frozen_string_literal: true

class DataMigrations::RecalculatePerTrackerTracksJob < ApplicationJob
  queue_as :data_migrations

  STAGGER_WINDOW_SECONDS = 3600

  def perform(user_id = nil)
    return enqueue_pending_users if user_id.nil?

    user = User.find_by(id: user_id)
    return unless user

    Points::TrackerIdBackfiller.new(user).call

    return unless user.tracks.where(tracker_id: nil).exists?

    Users::RecalculateDataJob.perform_now(user.id, notify: false)
  end

  private

  def enqueue_pending_users
    user_ids = User
               .where('EXISTS (SELECT 1 FROM tracks WHERE tracks.user_id = users.id AND tracks.tracker_id IS NULL)')
               .pluck(:id)
    return if user_ids.empty?

    Rails.logger.info(
      "[DataMigrations::RecalculatePerTrackerTracks] enqueuing recalculation for #{user_ids.size} user(s)"
    )

    user_ids.each do |id|
      delay = rand(0..STAGGER_WINDOW_SECONDS).seconds
      self.class.set(wait: delay).perform_later(id)
    end
  end
end
