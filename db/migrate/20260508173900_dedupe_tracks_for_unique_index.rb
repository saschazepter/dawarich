# frozen_string_literal: true

class DedupeTracksForUniqueIndex < ActiveRecord::Migration[8.0]
  BATCH_SIZE = 500

  disable_ddl_transaction!

  def up
    say_with_time('Deduplicating tracks by (user_id, start_at, end_at)') do
      total_losers = 0

      loop do
        groups = duplicate_groups(limit: BATCH_SIZE)
        break if groups.empty?

        groups.each do |group|
          loser_ids = resolve_group(group)
          total_losers += loser_ids.size
        end
      end

      say "Removed #{total_losers} duplicate track row(s)", true
    end
  end

  def down
    # Data deletion is not reversible. Down is a no-op so the schema migration
    # can roll back without errors. Restore from backup if rollback is needed.
  end

  private

  def duplicate_groups(limit:)
    sql = <<~SQL
      SELECT user_id, start_at, end_at, ARRAY_AGG(id ORDER BY id) AS ids
      FROM tracks
      GROUP BY user_id, start_at, end_at
      HAVING COUNT(*) > 1
      LIMIT #{limit.to_i}
    SQL

    connection.execute(sql).to_a
  end

  def resolve_group(row)
    ids = parse_id_array(row['ids'])
    return [] if ids.size < 2

    winner_id = pick_winner(ids)
    loser_ids = ids - [winner_id]

    Track.transaction do
      # Reassign points from losers to winner. Filter by track_id so we don't
      # rewrite points already on the winner.
      execute(
        "UPDATE points SET track_id = #{winner_id} " \
        "WHERE track_id IN (#{loser_ids.join(',')})"
      )

      # track_segments belong to losers; cascade via Track#destroy is too
      # heavy for a maintenance migration, so we delete segments first then
      # the losers themselves with a single statement each.
      execute("DELETE FROM track_segments WHERE track_id IN (#{loser_ids.join(',')})")
      execute("DELETE FROM tracks WHERE id IN (#{loser_ids.join(',')})")
    end

    loser_ids
  end

  def pick_winner(ids)
    # Pick the row with the longest distance, breaking ties by the lowest id
    # (oldest insert). Distance is in meters; nil distance loses to any
    # numeric distance.
    sql = <<~SQL
      SELECT id FROM tracks
      WHERE id IN (#{ids.join(',')})
      ORDER BY COALESCE(distance, 0) DESC, id ASC
      LIMIT 1
    SQL

    connection.execute(sql).first['id']
  end

  def parse_id_array(raw)
    case raw
    when Array then raw.map(&:to_i)
    when String then raw.delete('{}').split(',').map(&:to_i)
    else Array(raw).map(&:to_i)
    end
  end
end
