# frozen_string_literal: true

class Stats::BackfillTimezoneRebucketJob < ApplicationJob
  queue_as :stats

  def perform
    Stat.in_batches(of: 1000) do |batch|
      batch.pluck(:user_id, :year, :month).each do |user_id, year, month|
        Stats::CalculatingJob.perform_later(user_id, year, month)
      end
    end
  end
end
