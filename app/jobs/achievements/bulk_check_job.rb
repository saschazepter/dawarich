# frozen_string_literal: true

module Achievements
  class BulkCheckJob < ApplicationJob
    queue_as :default

    def perform
      user_ids = (User.active.pluck(:id) + User.trial.pluck(:id)).uniq

      user_ids.each do |user_id|
        Achievements::CheckJob.perform_later(user_id)
      end
    end
  end
end
