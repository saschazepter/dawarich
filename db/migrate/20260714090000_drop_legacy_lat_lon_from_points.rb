# frozen_string_literal: true

class DropLegacyLatLonFromPoints < ActiveRecord::Migration[8.0]
  def up
    return unless column_exists?(:points, :latitude) || column_exists?(:points, :longitude)

    Rails.logger.info '[DropLegacyLatLonFromPoints] starting'

    # Self-hosted instances upgrading from a pre-lonlat-backfill version still
    # carry coordinates only in the legacy columns; copy them before dropping.
    backfilled = execute(<<~SQL.squish).cmd_tuples
      UPDATE points
      SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
      WHERE lonlat IS NULL AND longitude IS NOT NULL AND latitude IS NOT NULL
    SQL
    Rails.logger.info "[DropLegacyLatLonFromPoints] backfilled lonlat for #{backfilled} points"

    execute "SET LOCAL lock_timeout = '5s'"
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS latitude'
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS longitude'
    Rails.logger.info '[DropLegacyLatLonFromPoints] done'
  end

  def down
    execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS latitude  numeric(10,6)'
    execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS longitude numeric(10,6)'
  end
end
