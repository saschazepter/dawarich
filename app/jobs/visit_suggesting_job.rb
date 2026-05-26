# frozen_string_literal: true

class VisitSuggestingJob < ApplicationJob
  include UserTimezone

  queue_as :visit_suggesting
  sidekiq_options retry: false

  # Passing timespan of more than 3 years somehow results in duplicated Places.
  # `realtime: true` signals this perform was triggered by Visits::RealtimeDebouncer;
  # clear the debounce key at start so the next inbound point can re-arm without
  # waiting for REDIS_KEY_TTL to expire.
  def perform(user_id:, start_at:, end_at:, realtime: false)
    user = find_user_or_skip(user_id) || return

    return unless user.safe_settings.visits_suggestions_enabled?

    Visits::RealtimeDebouncer.new(user_id).clear if realtime

    with_user_timezone(user) do
      start_time = parse_date(start_at)
      end_time = parse_date(end_at)

      # Create one-day chunks
      current_time = start_time
      while current_time < end_time
        chunk_end = [current_time + 1.day, end_time].min
        Visits::Suggest.new(user, start_at: current_time, end_at: chunk_end).call
        current_time += 1.day
      end
    end
  end

  private

  def parse_date(date)
    date.is_a?(String) ? Time.zone.parse(date) : date.to_datetime
  end
end
