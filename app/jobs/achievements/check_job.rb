# frozen_string_literal: true

module Achievements
  class CheckJob < ApplicationJob
    queue_as :achievements

    def perform(user_id, notify: true, oldest_timestamp: nil)
      user = User.find_by(id: user_id)
      return unless user

      notify &&= Flipper.enabled?(:achievements)

      Achievements::RegionSetChecker.new(user, notify: notify, oldest_timestamp: oldest_timestamp).call
    end
  end
end
