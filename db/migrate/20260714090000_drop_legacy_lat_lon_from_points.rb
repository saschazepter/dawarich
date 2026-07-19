# frozen_string_literal: true

class DropLegacyLatLonFromPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 50_000

  def up
    return unless column_exists?(:points, :latitude) || column_exists?(:points, :longitude)

    Rails.logger.info '[DropLegacyLatLonFromPoints] starting'

    # Self-hosted instances upgrading from a pre-lonlat-backfill version still
    # carry coordinates only in the legacy columns; copy them before dropping.
    # Guarded on both columns so a rerun after a partial failure skips straight
    # to the drop instead of referencing a missing column.
    if column_exists?(:points, :latitude) && column_exists?(:points, :longitude)
      backfilled = 0
      loop do
        updated = execute(<<~SQL.squish).cmd_tuples
          UPDATE points
          SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
          WHERE id IN (
            SELECT id FROM points
            WHERE lonlat IS NULL AND longitude IS NOT NULL AND latitude IS NOT NULL
            LIMIT #{BATCH_SIZE}
          )
        SQL
        backfilled += updated
        break if updated.zero?
      end
      Rails.logger.info "[DropLegacyLatLonFromPoints] backfilled lonlat for #{backfilled} points"
    end

    execute "SET lock_timeout = '5s'"
    # Single statement so both columns drop atomically and a rerun never sees
    # only one of them missing.
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude'
    execute 'RESET lock_timeout'
    Rails.logger.info '[DropLegacyLatLonFromPoints] done'
  end

  def down
    execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS latitude numeric(10,6), ' \
            'ADD COLUMN IF NOT EXISTS longitude numeric(10,6)'
  end
end
