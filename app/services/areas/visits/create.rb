# frozen_string_literal: true

# Deprecated. Retired in favor of Visits::SmartDetect on 2026-05-27. Cluster
# centroids that fall inside a user-defined Area are now attached via
# Visits::Creator#find_matching_area (creator.rb:69) on the DBSCAN output path.
#
# Stub remains for two-phase deploy safety. Delete ~30 days after retirement.
class Areas::Visits::Create
  def initialize(*); end

  def call(*)
    Rails.logger.info(
      '[Areas::Visits::Create] deprecated no-op invoked; SmartDetect + ' \
      'Creator#find_matching_area handle area attachment now'
    )
    nil
  end
end
