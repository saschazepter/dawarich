# frozen_string_literal: true

class Points::AnomalyFilterJob < ApplicationJob
  queue_as :low_priority

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3 do |job, error|
    user_id, start_time, end_time = job.arguments
    ExceptionReporter.call(
      error,
      "Points::AnomalyFilterJob retries exhausted user_id=#{user_id} range=#{start_time}..#{end_time}"
    )
  end

  def perform(user_id, start_time, end_time)
    Points::AnomalyFilter.new(user_id, start_time, end_time).call
  end
end
