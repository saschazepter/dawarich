# frozen_string_literal: true

# Runs daily at 00:05 to suggest visits for all users with the default timespan
# of 1 day. Visits::TimeChunks stretches same-year ranges to year-end; only
# invoke it for ranges that genuinely span multiple months.
class BulkVisitsSuggestingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  TIME_CHUNKS_THRESHOLD_DAYS = 32

  def perform(start_at: 1.day.ago.beginning_of_day, end_at: 1.day.ago.end_of_day, user_ids: [], user_id: nil)
    # Detection runs regardless of reverse_geocoding_enabled?. The Names::Suggester
    # returns nil when geodata is missing, and Place::DEFAULT_NAME covers the
    # fallback. Self-hosters without Photon still get clustered visits.
    user_ids = (Array(user_ids) | Array(user_id)).compact
    users = user_ids.any? ? User.active.where(id: user_ids) : User.active
    start_at = start_at.to_datetime
    end_at = end_at.to_datetime

    time_chunks = compute_time_chunks(start_at, end_at)

    users.active.find_each do |user|
      next unless user.safe_settings.visits_suggestions_enabled?
      next unless user.points_count&.positive?

      schedule_chunked_jobs(user, time_chunks)
    end
  end

  private

  def compute_time_chunks(start_at, end_at)
    if (end_at - start_at).to_f <= TIME_CHUNKS_THRESHOLD_DAYS
      [[start_at, end_at]]
    else
      Visits::TimeChunks.new(start_at:, end_at:).call
    end
  end

  def schedule_chunked_jobs(user, time_chunks)
    time_chunks.each do |time_chunk|
      VisitSuggestingJob.perform_later(
        user_id: user.id, start_at: time_chunk.first, end_at: time_chunk.last
      )
    end
  end
end
