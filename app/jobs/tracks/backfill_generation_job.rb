# frozen_string_literal: true

class Tracks::BackfillGenerationJob < ApplicationJob
  queue_as :tracks

  def perform(user_id)
    range = Tracks::BackfillScheduler.peek_range(user_id)
    return if range.nil?

    earliest, latest = range
    window_start = Tracks::IncrementalGenerator::LOOKBACK_HOURS.hours.ago

    Tracks::ParallelGeneratorJob.perform_later(
      user_id,
      start_at: Time.zone.at(earliest).beginning_of_day,
      end_at: [Time.zone.at(latest).end_of_day, window_start].min,
      mode: :bulk,
      untracked_only: true
    )

    Tracks::BackfillScheduler.clear(user_id)
  end
end
