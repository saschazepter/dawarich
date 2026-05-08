# frozen_string_literal: true

class Stats::BackfillTimezoneRebucketJob < ApplicationJob
  queue_as :stats

  JITTER_WINDOW = 2.hours

  def perform
    Stat.in_batches(of: 1000) do |batch|
      batch.pluck(:user_id, :year, :month).each do |user_id, year, month|
        Stats::CalculatingJob
          .set(wait: rand(0..JITTER_WINDOW.to_i).seconds)
          .perform_later(user_id, year, month)
      end
    end
  end
end
