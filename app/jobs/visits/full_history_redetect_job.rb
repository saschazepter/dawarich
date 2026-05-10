# frozen_string_literal: true

class Visits::FullHistoryRedetectJob < ApplicationJob
  queue_as :visit_suggesting

  BATCH_OVERLAP_SECONDS = 1.hour.to_i

  def perform(user_id)
    user = User.find(user_id)
    @user_id = user_id
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    acquire_lock(user_id)

    min_ts = user.points.minimum(:timestamp)
    max_ts = user.points.maximum(:timestamp)

    if min_ts.nil?
      notify(user, kind: :info, title: 'Visit re-detection',
                   content: 'No points to re-detect.')
      return
    end

    Rails.logger.info(
      "[Visits::FullHistoryRedetectJob start] user_id=#{user.id} " \
      "point_range=#{min_ts}..#{max_ts}"
    )

    visit_ids = user.visits.where(status: :suggested).pluck(:id)
    place_ids_direct    = Visit.where(id: visit_ids).where.not(place_id: nil).pluck(:place_id)
    place_ids_suggested = PlaceVisit.where(visit_id: visit_ids).pluck(:place_id)
    candidate_place_ids = (place_ids_direct + place_ids_suggested).uniq

    Visit.where(id: visit_ids).destroy_all

    months = monthly_ranges(min_ts, max_ts)
    visits_created = months.sum do |range_start, range_end|
      Visits::SmartDetect.new(user, start_at: range_start, end_at: range_end).call.size
    end

    places_deleted = cleanup_orphan_places(user, candidate_place_ids)

    user.update!(visits_redetected_at: Time.current)

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
    Rails.logger.info(
      "[Visits::FullHistoryRedetectJob done] user_id=#{user.id} " \
      "visits_created=#{visits_created} places_deleted=#{places_deleted} duration_ms=#{duration_ms}"
    )

    notify(user, kind: :info, title: 'Visit re-detection complete',
                 content: "#{visits_created} visits across #{months.size} months.")
  rescue StandardError => e
    Rails.logger.error(
      "[Visits::FullHistoryRedetectJob error] user_id=#{user_id} " \
      "class=#{e.class} message=#{e.message}"
    )
    user_for_notify = defined?(user) ? user : User.find_by(id: user_id)
    user_for_notify&.notifications&.create(
      kind: :error,
      title: 'Visit re-detection failed',
      content: e.message
    )
    ExceptionReporter.call(e)
    raise
  ensure
    release_lock(user_id)
  end

  private

  def acquire_lock(user_id)
    return unless advisory_locks_enabled?

    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_lock(?)', user_id.to_i])
    )
  end

  def release_lock(user_id)
    return unless advisory_locks_enabled?

    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_unlock(?)', user_id.to_i])
    )
  rescue StandardError
    nil
  end

  def advisory_locks_enabled?
    ActiveRecord::Base.connection_pool.db_config.configuration_hash[:advisory_locks] != false
  end

  def monthly_ranges(min_ts, max_ts)
    result = []
    cursor = Time.zone.at(min_ts).beginning_of_month
    while cursor.to_i < max_ts
      batch_start = [cursor.to_i, min_ts].max
      batch_end_raw = (cursor.end_of_month + 1.day).beginning_of_day.to_i - 1
      batch_end = [batch_end_raw + BATCH_OVERLAP_SECONDS, max_ts].min
      result << [batch_start, batch_end]
      cursor = cursor.next_month
    end
    result
  end

  def cleanup_orphan_places(user, candidate_place_ids)
    return 0 if candidate_place_ids.empty?

    deleted = 0
    Place.photon.where(id: candidate_place_ids, user_id: user.id).find_each do |place|
      next if place.visits.exists? || place.place_visits.exists?

      place.destroy
      deleted += 1
    end
    deleted
  end

  def notify(user, kind:, title:, content:)
    user.notifications.create(kind: kind, title: title, content: content)
  end
end
