# frozen_string_literal: true

class BackfillUserIdOnPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    return if Place.where(user_id: nil).none?

    deleted_orphans = 0
    assigned = 0

    Place.where(user_id: nil).find_each(batch_size: 500) do |place|
      winner_user_id = ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT visits.user_id
        FROM place_visits
        JOIN visits ON visits.id = place_visits.visit_id
        WHERE place_visits.place_id = #{place.id}
        GROUP BY visits.user_id
        ORDER BY COUNT(*) DESC, MAX(visits.started_at) DESC, visits.user_id ASC
        LIMIT 1
      SQL

      if winner_user_id.nil?
        place.delete
        deleted_orphans += 1
      else
        place.update_columns(user_id: winner_user_id, updated_at: Time.current)
        assigned += 1
      end
    end

    say_with_time "Backfill summary: assigned=#{assigned}, deleted_orphans=#{deleted_orphans}" do
      # no-op, just for logging
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Cannot un-backfill user_id; orphan places were deleted'
  end
end
