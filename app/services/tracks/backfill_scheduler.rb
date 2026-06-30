# frozen_string_literal: true

class Tracks::BackfillScheduler
  def initialize(user_id, timestamps)
    @user_id = user_id
    @timestamps = timestamps.compact
  end

  def call
    return if @timestamps.empty?

    earliest = @timestamps.min
    return if earliest >= realtime_window_start

    Tracks::ParallelGeneratorJob.perform_later(
      @user_id,
      start_at: Time.zone.at(earliest).beginning_of_day,
      end_at: Time.zone.at(@timestamps.max).end_of_day,
      mode: :bulk,
      untracked_only: true
    )
  end

  private

  def realtime_window_start
    Tracks::IncrementalGenerator::LOOKBACK_HOURS.hours.ago.to_i
  end
end
