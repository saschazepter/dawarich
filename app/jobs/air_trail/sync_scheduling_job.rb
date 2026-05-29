# frozen_string_literal: true

module AirTrail
  class SyncSchedulingJob < ApplicationJob
    queue_as :imports

    def perform
      User.find_each do |user|
        settings = user.safe_settings
        next if settings.airtrail_url.blank? || settings.airtrail_api_key.blank?

        AirTrail::ImportFlightsJob.perform_later(user.id)
      end
    end
  end
end
