# frozen_string_literal: true

class Points::Destroyer
  def initialize(user, point_ids)
    @user = user
    @point_ids = Array(point_ids)
  end

  def call
    affected_track_ids = nil
    destroyed = nil

    ActiveRecord::Base.transaction do
      affected_track_ids = user.points
                               .where(id: point_ids)
                               .where.not(track_id: nil)
                               .distinct
                               .pluck(:track_id)
      destroyed = user.points.where(id: point_ids).destroy_all
    end

    return destroyed if destroyed.empty?

    User.update_counters(user.id, points_count: -destroyed.count)

    enqueue_stats_recalculation(destroyed)
    enqueue_track_recalculation(affected_track_ids, destroyed.count)

    destroyed
  end

  private

  attr_reader :user, :point_ids

  def enqueue_stats_recalculation(destroyed)
    destroyed
      .map { |point| Time.zone.at(point.timestamp) }
      .map { |time| [time.year, time.month] }
      .uniq
      .each { |year, month| Stats::CalculatingJob.perform_later(user.id, year, month) }
  end

  def enqueue_track_recalculation(track_ids, deleted_count)
    return if track_ids.empty?

    Rails.logger.info(
      "[Points::Destroyer] deleted #{deleted_count} points, " \
      "enqueuing Tracks::RecalculateJob for #{track_ids.size} tracks: #{track_ids.inspect}"
    )
    track_ids.each { |track_id| Tracks::RecalculateJob.perform_later(track_id) }
  end
end
