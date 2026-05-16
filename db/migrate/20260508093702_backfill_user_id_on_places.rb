# frozen_string_literal: true

class BackfillUserIdOnPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    return if Place.where(user_id: nil).none?

    deleted_orphans = 0
    assigned = 0
    skipped_failed = 0

    Place.where(user_id: nil).find_each(batch_size: 500) do |place|
      winner_user_id = ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT user_id
        FROM (
          SELECT visits.user_id AS user_id, visits.started_at AS ts
          FROM place_visits
          JOIN visits ON visits.id = place_visits.visit_id
          WHERE place_visits.place_id = #{place.id}
          UNION ALL
          SELECT visits.user_id AS user_id, visits.started_at AS ts
          FROM visits
          WHERE visits.place_id = #{place.id}
        ) sub
        GROUP BY user_id
        ORDER BY COUNT(*) DESC, MAX(ts) DESC, user_id ASC
        LIMIT 1
      SQL

      if winner_user_id.nil?
        place.delete
        deleted_orphans += 1
      else
        place.update_columns(user_id: winner_user_id, updated_at: Time.current)
        assigned += 1
      end
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotUnique => e
      Rails.logger.error("Backfill skipped place=#{place.id}: #{e.class} #{e.message}")
      skipped_failed += 1
    end

    Rails.logger.info(
      "Places backfill: assigned=#{assigned}, deleted_orphans=#{deleted_orphans}, skipped_failed=#{skipped_failed}"
    )

    return if skipped_failed.zero?

    raise "Places backfill finished with #{skipped_failed} skipped rows; investigate before running Stage 2."
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Cannot un-backfill user_id; orphan places were deleted'
  end
end
