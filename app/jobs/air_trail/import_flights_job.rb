# frozen_string_literal: true

module AirTrail
  class ImportFlightsJob < ApplicationJob
    queue_as :imports

    def perform(user_id)
      user = find_user_or_skip(user_id) || return

      AirTrail::ImportFlights.new(user).call
    end
  end
end
