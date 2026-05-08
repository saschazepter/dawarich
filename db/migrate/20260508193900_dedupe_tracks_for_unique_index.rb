# frozen_string_literal: true

# Cleans up any (user_id, start_at, end_at) duplicate Track rows so the unique
# index in the next migration can apply. Per (user_id, start_at, end_at) group
# we keep the row with the highest id (newest insert) and delete the rest plus
# their track_segments — same winner-selection and SQL shape as
# Tracks::Deduplicator, just executed inline at deploy time so the index
# migration that follows doesn't fail on existing dups.
class DedupeTracksForUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    user_ids = users_with_duplicates
    return if user_ids.empty?

    Rails.logger.info "[Migration] Deduplicating tracks for #{user_ids.size} user(s)"

    user_ids.each do |user_id|
      removed = dedupe_user(user_id)
      next if removed.zero?

      Rails.logger.info "[Migration] user_id=#{user_id} removed=#{removed} duplicate track(s)"
    end
  end

  def down
    # Data deletion is not reversible. Restore from backup if rollback is needed.
  end

  private

  def users_with_duplicates
    sql = <<~SQL.squish
      SELECT DISTINCT user_id FROM tracks
      WHERE (user_id, start_at, end_at) IN (
        SELECT user_id, start_at, end_at FROM tracks
        GROUP BY user_id, start_at, end_at
        HAVING COUNT(*) > 1
      )
    SQL
    connection.execute(sql).map { |row| row['user_id'].to_i }
  end

  def dedupe_user(user_id)
    ActiveRecord::Base.transaction do
      connection.execute(
        ActiveRecord::Base.sanitize_sql([<<~SQL.squish, { user_id: user_id }])
          DELETE FROM track_segments
          WHERE track_id IN (
            SELECT id FROM tracks
            WHERE user_id = :user_id
              AND id NOT IN (
                SELECT MAX(id) FROM tracks
                WHERE user_id = :user_id
                GROUP BY start_at, end_at
              )
          )
        SQL
      )

      result = connection.execute(
        ActiveRecord::Base.sanitize_sql([<<~SQL.squish, { user_id: user_id }])
          DELETE FROM tracks
          WHERE user_id = :user_id
            AND id NOT IN (
              SELECT MAX(id) FROM tracks
              WHERE user_id = :user_id
              GROUP BY start_at, end_at
            )
        SQL
      )

      result.cmd_tuples
    end
  end
end
