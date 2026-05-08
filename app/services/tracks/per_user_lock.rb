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
    DEFAULT_ACQUIRE_TIMEOUT = 30.0
    POLL_INTERVAL = 0.1

    class AcquisitionTimeout < StandardError; end

    def self.with_user_lock(user_id, timeout: DEFAULT_ACQUIRE_TIMEOUT)
      # Pin the connection for the entire acquire→yield→release window so the
      # release runs on the same Postgres session that took the lock. Without
      # this, Sidekiq's auto-checkin can release the connection back to the
      # pool mid-block, and the unlock SQL silently no-ops on a different
      # session — leaving the original session locked until it terminates.
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        acquired = false
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          acquired = try_acquire(conn, user_id, timeout, started_at)

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

    # Polls `pg_try_advisory_lock` until success or timeout. Raises
    # AcquisitionTimeout on miss so the caller (typically a Sidekiq job) can
    # retry instead of blocking forever behind a stuck holder.
    def self.try_acquire(conn, user_id, timeout, started_at)
      loop do
        result = conn.execute(try_acquire_sql(user_id)).first
        got_lock = result && [true, 't'].include?(result['pg_try_advisory_lock'])
        return true if got_lock

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        if elapsed >= timeout
          raise AcquisitionTimeout,
                "Tracks::PerUserLock: could not acquire lock for user_id=#{user_id} " \
                "within #{timeout}s"
        end

        sleep POLL_INTERVAL
      end
    end

    def self.try_acquire_sql(user_id)
      ActiveRecord::Base.send(
        :sanitize_sql_array,
        ['SELECT pg_try_advisory_lock(?, ?)', LOCK_NAMESPACE, user_id]
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
