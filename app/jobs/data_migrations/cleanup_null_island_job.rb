# frozen_string_literal: true

class DataMigrations::CleanupNullIslandJob < ApplicationJob
  queue_as :data_migrations

  def perform(user_id = nil)
    return fan_out if user_id.nil?

    user = find_user_or_skip(user_id) || return

    zero_points = user.points.null_island
    track_ids = zero_points.where.not(track_id: nil).distinct.pluck(:track_id)
    affected_months = zero_points.pluck(:timestamp).map do |timestamp|
      time = Time.zone.at(timestamp)
      [time.year, time.month]
    end.uniq

    zero_points.update_all(anomaly: true, updated_at: Time.current)
    destroy_null_island_visits(user)

    affected_months.each { |year, month| Stats::CalculatingJob.perform_later(user.id, year, month) }
    track_ids.each { |track_id| Tracks::RecalculateJob.perform_later(track_id) }
  end

  private

  def fan_out
    User.where(id: Point.null_island.select(:user_id).distinct)
        .pluck(:id)
        .each { |user_id| self.class.perform_later(user_id) }
  end

  def destroy_null_island_visits(user)
    user.visits
        .joins(:place)
        .where(Points::NullIsland.sql_predicate('places.lonlat'))
        .destroy_all
  end
end
