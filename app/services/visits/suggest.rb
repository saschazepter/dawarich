# frozen_string_literal: true

class Visits::Suggest
  attr_reader :user, :start_at, :end_at

  def initialize(user, start_at:, end_at:)
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @user = user
  end

  # Returns `{ visits: Array<Visit>, place_ids: Array<Integer> }`. Caller
  # (VisitSuggestingJob) accumulates across day-chunks and emits one notification
  # at end of job — Suggest no longer creates per-chunk notifications.
  # Rescue branch returns the empty hash so callers can safely accumulate.
  # Narrow rescue: only known-transient infrastructure errors are caught and
  # converted to a notification. Programming errors and unknown StandardErrors
  # propagate to Sidekiq, which retries (retry: 2 on VisitSuggestingJob) and
  # then dead-letters to Sentry via the normal Sidekiq error path.
  RESCUED_ERRORS = [
    Tracks::PerUserLock::AcquisitionTimeout,
    ActiveRecord::QueryCanceled,
    ActiveRecord::ConnectionTimeoutError
  ].freeze

  def call
    visits = Visits::SmartDetect.new(user, start_at:, end_at:).call
    place_ids = visits.filter_map(&:place_id).uniq

    { visits: visits, place_ids: place_ids }
  rescue *RESCUED_ERRORS => e
    user.notifications.create!(
      kind: :error,
      title: 'Visit detection failed',
      content: "We couldn't detect visits for the selected range. " \
               'The team has been notified; please retry from Settings → Visits.'
    )
    ExceptionReporter.call(e)

    { visits: [], place_ids: [] }
  end
end
