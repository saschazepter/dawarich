# frozen_string_literal: true

module Imports
  class ExtractionPolicy < ApplicationPolicy
    IN_FLIGHT = %w[pending running].freeze

    def create?
      user.present? &&
        record.user == user &&
        record.additional_data_extraction_supported? &&
        !in_flight?
    end

    def destroy?
      user.present? &&
        record.user == user &&
        record.additional_data_extraction_supported? &&
        !in_flight? &&
        !record.additional_data_extraction_not_attempted?
    end

    private

    # A second job would rebuild segments underneath the one already running.
    # Sidekiq loses in-flight jobs on SIGKILL, so a run that never reported back
    # stops counting after STALE_AFTER and the user can retry.
    STALE_AFTER = 6.hours

    def in_flight?
      return false unless IN_FLIGHT.include?(record.additional_data_extraction_status.to_s)

      started_at = record.additional_data_extraction['started_at']
      return true if started_at.blank?

      Time.zone.parse(started_at.to_s) > STALE_AFTER.ago
    rescue ArgumentError, TypeError
      true
    end
  end
end
