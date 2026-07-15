# frozen_string_literal: true

module Achievements
  class BulkCheckJob < ApplicationJob
    queue_as :achievements

    def perform
      user_ids = (User.active.pluck(:id) + User.trial.pluck(:id)).uniq

      ActiveJob.perform_all_later(user_ids.map { |user_id| Achievements::CheckJob.new(user_id) })
    end
  end
end
