# frozen_string_literal: true

# Deprecated. Retired 2026-05-27. SmartDetect handles place-visit attachment
# via Visits::PlaceFinder on the DBSCAN path. This stub catches any in-flight
# enqueued jobs at deploy time and exits cleanly. Delete ~30 days after
# retirement.
class PlaceVisitsCalculatingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(*)
    Rails.logger.info('[PlaceVisitsCalculatingJob] deprecated no-op; SmartDetect handles this now')
  end
end
