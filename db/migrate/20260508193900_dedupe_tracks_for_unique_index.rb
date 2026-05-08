# frozen_string_literal: true

class DedupeTracksForUniqueIndex < ActiveRecord::Migration[8.0]
  BATCH_SIZE = 500

  disable_ddl_transaction!

  def up
    say_with_time('Deduplicating tracks by (user_id, start_at, end_at)') do
      total_losers = 0
      total_orphaned = 0
      iteration = 0
      previous_signature = nil

      loop do
        iteration += 1
        groups = duplicate_groups(limit: BATCH_SIZE)
        break if groups.empty?

        # If two consecutive iterations return the exact same set of duplicate
        # groups, the resolve loop is making no progress (e.g. a future FK
        # blocking deletion) — raise rather than spin forever.
        signature = groups.map { |g| [g['user_id'], g['start_at'], g['end_at']] }
        if signature == previous_signature
          raise(
            "Dedup migration stuck: same #{groups.size} duplicate group(s) returned " \
            'in two consecutive batches without making progress.'
          )
        end
        previous_signature = signature

        batch_losers = 0
        batch_orphaned = 0
        groups.each do |group|
          stats = resolve_group(group)
          batch_losers += stats[:losers]
          batch_orphaned += stats[:orphaned]
        end
        total_losers += batch_losers
        total_orphaned += batch_orphaned

        say(
          "Batch #{iteration}: #{groups.size} group(s), #{batch_losers} loser(s) deleted, " \
          "#{batch_orphaned} point(s) orphaned for re-attachment " \
          "(running totals: #{total_losers}/#{total_orphaned})",
          true
        )
      end

      say "Removed #{total_losers} duplicate track row(s); orphaned #{total_orphaned} out-of-window point(s)", true
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
    return { losers: 0, orphaned: 0 } if ids.size < 2

    winner_id, winner_start, winner_end = pick_winner(ids)
    loser_ids = ids - [winner_id]

    # Defense-in-depth: if the winner somehow ended up in loser_ids (type
    # mismatch, etc.), abort this group rather than delete the winner.
    if loser_ids.empty? || loser_ids.include?(winner_id)
      raise "Dedup migration safety check failed: winner_id=#{winner_id.inspect} losers=#{loser_ids.inspect}"
    end

    orphaned = 0
    Track.transaction do
      # Reassign loser points within the winner's time window only — points
      # outside that window would silently corrupt the winner's path/distance/
      # duration metadata, which were computed from the winner's original point
      # set. Out-of-window points are nulled so the next regeneration pass can
      # re-attach them to a track that actually covers their timestamps.
      window_start = winner_start.to_i
      window_end = winner_end.to_i

      connection.execute(
        ActiveRecord::Base.send(
          :sanitize_sql_array,
          [
            "UPDATE points SET track_id = ? WHERE track_id IN (#{loser_ids.join(',')}) " \
            'AND timestamp BETWEEN ? AND ?',
            winner_id, window_start, window_end
          ]
        )
      )

      orphan_result = connection.execute(
        "UPDATE points SET track_id = NULL WHERE track_id IN (#{loser_ids.join(',')})"
      )
      orphaned = orphan_result.cmd_tuples

      # track_segments belong to losers; cascade via Track#destroy is too
      # heavy for a maintenance migration, so we delete segments first then
      # the losers themselves.
      connection.execute("DELETE FROM track_segments WHERE track_id IN (#{loser_ids.join(',')})")
      connection.execute("DELETE FROM tracks WHERE id IN (#{loser_ids.join(',')})")
    end

    { losers: loser_ids.size, orphaned: orphaned }
  end

  # Picks the row with the most associated points (most data is the best
  # signal of "real" track), breaking ties by longest distance and finally
  # by oldest id. Returns [id, start_at, end_at] for the winner so the caller
  # can constrain point reassignment to the winner's time window.
  def pick_winner(ids)
    sql = <<~SQL
      SELECT t.id, t.start_at, t.end_at, COALESCE(t.distance, 0) AS dist,
             COUNT(p.id) AS point_count
      FROM tracks t
      LEFT JOIN points p ON p.track_id = t.id
      WHERE t.id IN (#{ids.join(',')})
      GROUP BY t.id, t.start_at, t.end_at, t.distance
      ORDER BY point_count DESC, dist DESC, t.id ASC
      LIMIT 1
    SQL

    row = connection.execute(sql).first
    raise "Dedup migration: no winner found for ids=#{ids.inspect}" unless row

    # `connection.execute` skips Rails type casting and returns raw strings.
    # Coerce explicitly so Array#- and arithmetic work correctly downstream.
    [
      row['id'].to_i,
      coerce_time(row['start_at']),
      coerce_time(row['end_at'])
    ]
  end

  def coerce_time(value)
    return value if value.is_a?(Time) || value.is_a?(DateTime)

    Time.zone.parse(value.to_s)
  end

  def parse_id_array(raw)
    case raw
    when Array then raw.map(&:to_i)
    when String then raw.delete('{}').split(',').map(&:to_i)
    else Array(raw).map(&:to_i)
    end
  end
end
