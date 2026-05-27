# frozen_string_literal: true

# Deprecated. Retired in favor of Visits::SmartDetect (DBSCAN-based) on
# 2026-05-27. This stub remains for two-phase deploy safety so any in-flight
# Sidekiq jobs (AreaVisitsCalculatingJob / PlaceVisitsCalculatingJob) that
# reference this class do not NameError on dequeue.
#
# Scheduled for deletion ~30 days after the retirement deploys (separate PR).
class Visits::Group
  def initialize(*); end

  def call(*)
    Rails.logger.info('[Visits::Group] deprecated no-op invoked; SmartDetect handles detection now')
    {}
  end
end
