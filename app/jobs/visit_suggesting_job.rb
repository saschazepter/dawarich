# frozen_string_literal: true

class VisitSuggestingJob < ApplicationJob
  include UserTimezone

  queue_as :visit_suggesting
  # Up to 3 attempts total. Sidekiq's default backoff handles transient
  # infrastructure failures (Redis/PG hiccups) that Visits::Suggest does NOT
  # rescue. After all retries, Sidekiq dead-letters to Sentry normally.
  sidekiq_options retry: 2

  # Passing timespan of more than 3 years somehow results in duplicated Places.
  # `realtime: true` signals this perform was triggered by Visits::RealtimeDebouncer;
  # clear the debounce key at start so the next inbound point can re-arm without
  # waiting for REDIS_KEY_TTL to expire.
  def perform(user_id:, start_at:, end_at:, realtime: false)
    user = find_user_or_skip(user_id) || return

    return unless user.safe_settings.visits_suggestions_enabled?

    Visits::RealtimeDebouncer.new(user_id).clear if realtime

    visit_count = 0
    place_ids = []
    earliest = nil
    latest = nil

    with_user_timezone(user) do
      start_time = parse_date(start_at)
      end_time = parse_date(end_at)

      current_time = start_time
      while current_time < end_time
        chunk_end = [current_time + 1.day, end_time].min
        result = Visits::Suggest.new(user, start_at: current_time, end_at: chunk_end).call || {}
        chunk_visits = Array(result[:visits])
        if chunk_visits.any?
          visit_count += chunk_visits.size
          place_ids.concat(Array(result[:place_ids]))
          earliest ||= current_time
          latest = chunk_end
        end
        current_time += 1.day
      end
    end

    emit_summary_notification(user, visit_count, earliest, latest) if visit_count.positive?
    enqueue_reverse_geocoding(place_ids.uniq)
  end

  private

  def parse_date(date)
    date.is_a?(String) ? Time.zone.parse(date) : date.to_datetime
  end

  def emit_summary_notification(user, count, earliest, latest)
    user.notifications.create!(
      kind: :info,
      title: 'New visits suggested',
      content: "#{count} new #{'visit'.pluralize(count)} suggested " \
               "from #{earliest.to_date} to #{latest.to_date}. " \
               'You can review them on the ' \
               '<a href="/map/v2?panel=timeline&status=suggested" class="link">Timeline</a> page.'
    )
  end

  def enqueue_reverse_geocoding(place_ids)
    return unless DawarichSettings.reverse_geocoding_enabled?

    place_ids.each { |id| ReverseGeocodingJob.perform_later('place', id) }
  end
end
