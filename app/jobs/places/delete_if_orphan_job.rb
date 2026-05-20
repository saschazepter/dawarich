# frozen_string_literal: true

module Places
  class DeleteIfOrphanJob < ApplicationJob
    queue_as :default

    def perform(place_id)
      Places::DeleteIfOrphan.call(place_id)
    end
  end
end
