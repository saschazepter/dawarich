# frozen_string_literal: true

class Visits::FullHistoryRedetectJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    raise NotImplementedError, 'Visits::FullHistoryRedetectJob implementation lands in Task 10'
  end
end
