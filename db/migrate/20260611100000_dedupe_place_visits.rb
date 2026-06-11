# frozen_string_literal: true

class DedupePlaceVisits < ActiveRecord::Migration[8.0]
  def up
    loop do
      duplicates = ActiveRecord::Base.connection.select_all(<<~SQL.squish)
        SELECT user_id, place_id, started_at, COUNT(*) AS cnt
        FROM visits
        WHERE place_id IS NOT NULL
        GROUP BY user_id, place_id, started_at
        HAVING COUNT(*) > 1
        LIMIT 100
      SQL

      break if duplicates.empty?

      Rails.logger.info("event=dedupe_place_visits batch_size=#{duplicates.count}")

      duplicates.each do |row|
        user_id    = row['user_id']
        place_id   = row['place_id']
        started_at = row['started_at']

        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          WITH ranked AS (
            SELECT id,
                   ROW_NUMBER() OVER (
                     PARTITION BY user_id, place_id, started_at
                     ORDER BY (CASE status WHEN 1 THEN 0 WHEN 0 THEN 1 WHEN 2 THEN 2 ELSE 3 END) ASC, id ASC
                   ) AS rn
            FROM visits
            WHERE user_id   = #{ActiveRecord::Base.connection.quote(user_id)}
              AND place_id  = #{ActiveRecord::Base.connection.quote(place_id)}
              AND started_at = #{ActiveRecord::Base.connection.quote(started_at)}
          ),
          keeper AS (
            SELECT id FROM ranked WHERE rn = 1
          ),
          dupes AS (
            SELECT id FROM ranked WHERE rn > 1
          )
          UPDATE points
             SET visit_id = (SELECT id FROM keeper)
           WHERE visit_id IN (SELECT id FROM dupes)
        SQL

        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          WITH ranked AS (
            SELECT id,
                   ROW_NUMBER() OVER (
                     PARTITION BY user_id, place_id, started_at
                     ORDER BY (CASE status WHEN 1 THEN 0 WHEN 0 THEN 1 WHEN 2 THEN 2 ELSE 3 END) ASC, id ASC
                   ) AS rn
            FROM visits
            WHERE user_id   = #{ActiveRecord::Base.connection.quote(user_id)}
              AND place_id  = #{ActiveRecord::Base.connection.quote(place_id)}
              AND started_at = #{ActiveRecord::Base.connection.quote(started_at)}
          )
          DELETE FROM visits WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
        SQL
      end
    end
  end

  def down
    Rails.logger.info('event=dedupe_place_visits_rollback action=no_op')
  end
end
