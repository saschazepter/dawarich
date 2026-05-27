# frozen_string_literal: true

# Deprecated. Retired in favor of Visits::SmartDetect on 2026-05-27. User
# places are now attached on the DBSCAN output path via Visits::PlaceFinder
# (which uses user.places.near + ST_DWithin against lonlat).
#
# Stub remains for two-phase deploy safety. Delete ~30 days after retirement.
class Places::Visits::Create
  def initialize(*); end

  def call(*)
    Rails.logger.info(
      '[Places::Visits::Create] deprecated no-op invoked; SmartDetect + ' \
      'PlaceFinder handle place attachment now'
    )
    nil
  end
end
