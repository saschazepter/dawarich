# frozen_string_literal: true

# Deprecated. Retired 2026-05-27 along with the 00:00 cron entry that scheduled
# it. BulkVisitsSuggestingJob's 00:05 cron covers visit detection now.
#
# Stub remains for two-phase deploy safety (catches any in-flight enqueued
# instances and exits cleanly). Delete ~30 days after retirement.
class AreaVisitsCalculationSchedulingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(*)
    Rails.logger.info(
      '[AreaVisitsCalculationSchedulingJob] deprecated no-op; BulkVisitsSuggestingJob handles scheduling now'
    )
  end
end
