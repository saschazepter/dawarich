# frozen_string_literal: true

class Points::AnomalyFilterJob < ApplicationJob
  queue_as :low_priority

  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  def perform(user_id, start_time, end_time)
    Points::AnomalyFilter.new(user_id, start_time, end_time).call
  end
end
