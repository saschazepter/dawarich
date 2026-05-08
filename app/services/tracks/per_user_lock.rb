# frozen_string_literal: true

# Advisory lock helpers for serializing per-user work that mutates Track rows.
#
# Advisory lock namespace registry — extend this list when adding a new use
# case and reserve a unique integer so namespaces never collide:
#
#   4242 — Tracks::PerUserLock (this module)
#
module Tracks
  module PerUserLock
    LOCK_NAMESPACE = 4242
    LOCK_WAIT_WARN_SECONDS = 1.0

    def self.with_user_lock(user_id)
      # Pin the connection for the entire acquire→yield→release window so the
      # release runs on the same Postgres session that took the lock. Without
      # this, Sidekiq's auto-checkin can release the connection back to the
      # pool mid-block, and the unlock SQL silently no-ops on a different
      # session — leaving the original session locked until it terminates.
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        acquired = false
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          conn.execute(acquire_sql(user_id))
          acquired = true

          waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          if waited >= LOCK_WAIT_WARN_SECONDS
            Rails.logger.warn(
              "event=tracks.per_user_lock_contention user_id=#{user_id} " \
              "waited_seconds=#{waited.round(3)}"
            )
          end

          yield
        ensure
          conn.execute(release_sql(user_id)) if acquired
        end
      end
    end

    def self.acquire_sql(user_id)
      ActiveRecord::Base.send(
        :sanitize_sql_array,
        ['SELECT pg_advisory_lock(?, ?)', LOCK_NAMESPACE, user_id]
      )
    end

    def self.release_sql(user_id)
      ActiveRecord::Base.send(
        :sanitize_sql_array,
        ['SELECT pg_advisory_unlock(?, ?)', LOCK_NAMESPACE, user_id]
      )
    end
  end
end
