# frozen_string_literal: true

class Tracks::BackfillGenerationJob < ApplicationJob
  queue_as :tracks

  def perform(user_id)
    range = Tracks::BackfillScheduler.pop_range(user_id)
    return if range.nil?

    earliest, latest = range

    Tracks::ParallelGeneratorJob.perform_later(
      user_id,
      start_at: Time.zone.at(earliest).beginning_of_day,
      end_at: Time.zone.at(latest).end_of_day,
      mode: :bulk,
      untracked_only: true
    )
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to schedule backfill track generation for user #{user_id}")
  end
end
