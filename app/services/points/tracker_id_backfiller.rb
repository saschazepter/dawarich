# frozen_string_literal: true

class Points::TrackerIdBackfiller
  BATCH_SIZE = 5_000

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    total = 0

    loop do
      updated = update_batch
      break if updated.zero?

      total += updated
    end

    Rails.logger.info("[Points::TrackerIdBackfiller] user_id=#{user.id} backfilled=#{total}") if total.positive?

    total
  end

  private

  def update_batch
    sql = <<~SQL.squish
      WITH batch AS (
        SELECT id FROM points
        WHERE user_id = #{user.id.to_i}
          AND tracker_id IS NULL
          AND (
            raw_data->>'deviceTag' IS NOT NULL
            OR raw_data->>'tid' IS NOT NULL
            OR import_id IS NOT NULL
          )
        LIMIT #{BATCH_SIZE}
      )
      UPDATE points
      SET
        tracker_id = (
          CASE
            WHEN points.raw_data->>'deviceTag' IS NOT NULL
              THEN 'google-records-device-' || (points.raw_data->>'deviceTag')
            WHEN points.raw_data->>'tid' IS NOT NULL
              THEN points.raw_data->>'tid'
            ELSE 'legacy-import-' || points.import_id::text
          END
        ),
        updated_at = NOW()
      FROM batch
      WHERE points.id = batch.id
    SQL

    ActiveRecord::Base.connection.exec_update(sql, 'TrackerIdBackfill')
  end
end
