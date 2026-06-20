# frozen_string_literal: true

class CleanUpAndConstrainNullLonlatPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  CONSTRAINT_NAME = 'points_lonlat_null'
  BATCH_SIZE = 10_000

  def up
    backfill_lonlat_from_legacy_columns
    delete_points_without_coordinates

    return if constraint_present?

    add_check_constraint :points, 'lonlat IS NOT NULL', name: CONSTRAINT_NAME, validate: false
  end

  def down
    # Points deleted in `up` are not recoverable; this only drops the constraint.
    remove_check_constraint :points, name: CONSTRAINT_NAME if constraint_present?
  end

  private

  def backfill_lonlat_from_legacy_columns
    backfilled = 0

    Point.where(lonlat: nil).where.not(latitude: nil).where.not(longitude: nil)
         .in_batches(of: BATCH_SIZE) do |batch|
      backfilled += batch.update_all('lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)')
    end

    Rails.logger.info("[#{self.class.name}] backfilled #{backfilled} point(s) from legacy latitude/longitude")
  end

  def delete_points_without_coordinates
    affected_user_ids = Set.new
    deleted = 0

    Point.where(lonlat: nil).in_batches(of: BATCH_SIZE) do |batch|
      affected_user_ids.merge(batch.distinct.pluck(:user_id))
      deleted += batch.delete_all
    end

    Rails.logger.info("[#{self.class.name}] deleted #{deleted} point(s) without coordinates")

    resync_points_counters(affected_user_ids)
  end

  def resync_points_counters(user_ids)
    ids = user_ids.compact
    return if ids.empty?

    User.unscoped.where(id: ids).update_all(
      'points_count = (SELECT COUNT(*) FROM points WHERE points.user_id = users.id)'
    )
  end

  def constraint_present?
    select_value("SELECT 1 FROM pg_constraint WHERE conname = #{quote(CONSTRAINT_NAME)}").present?
  end
end
