# frozen_string_literal: true

module Tracks
  module PerUserLock
    NAMESPACE = 'tracks:per_user_lock'
    DEFAULT_ACQUIRE_TIMEOUT = 30.0
    DEFAULT_TTL = 30.minutes
    POLL_INTERVAL = 0.1
    LOCK_WAIT_WARN_SECONDS = 1.0

    RELEASE_LUA = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    LUA

    # Token-verified EXPIRE: refreshes the lock's TTL ONLY if the caller still
    # holds the lock (token match). Prevents a zombie heartbeat thread from a
    # previously-crashed lock owner from extending a NEW owner's lock.
    EXPIRE_LUA = <<~LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("expire", KEYS[1], ARGV[2])
      else
        return 0
      end
    LUA

    DEFAULT_HEARTBEAT = 5.minutes
    DEFAULT_MAX_WALL = 2.hours
    HEARTBEAT_TICK = 1.second # cooperative-shutdown granularity

    class AcquisitionTimeout < StandardError; end

    def self.with_user_lock(user_id, timeout: DEFAULT_ACQUIRE_TIMEOUT, ttl: DEFAULT_TTL)
      key = "#{NAMESPACE}:#{user_id}"
      thread_key = :"per_user_lock_#{key}"

      # Reentrancy: if this thread already holds the lock for this key (e.g.
      # FullHistoryRedetectJob holds the lock and then calls SmartDetect, which
      # post-Phase-2 also wraps in PerUserLock), yield without re-acquiring.
      return yield if Thread.current[thread_key]

      token = SecureRandom.uuid
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      acquire!(key, token, ttl, timeout, user_id, started_at)
      Thread.current[thread_key] = token

      begin
        yield
      ensure
        Thread.current[thread_key] = nil
        release(key, token)
      end
    end

    def self.acquire!(key, token, ttl, timeout, user_id, started_at)
      deadline = started_at + timeout

      loop do
        acquired = Sidekiq.redis { |r| r.set(key, token, nx: true, ex: ttl.to_i) }
        if acquired
          waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          if waited >= LOCK_WAIT_WARN_SECONDS
            Rails.logger.warn(
              "event=tracks.per_user_lock_contention user_id=#{user_id} " \
              "waited_seconds=#{waited.round(3)}"
            )
          end
          return true
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise AcquisitionTimeout,
                "Tracks::PerUserLock: could not acquire lock for user_id=#{user_id} " \
                "within #{timeout}s"
        end

        sleep POLL_INTERVAL
      end
    end

    def self.release(key, token)
      Sidekiq.redis { |r| r.call('EVAL', RELEASE_LUA, 1, key, token) }
    end

    # Like with_user_lock, but spawns a background thread that periodically
    # refreshes the lock's TTL via a token-verified EXPIRE. Useful for
    # long-running operations (FullHistoryRedetectJob) where a 2h wall TTL
    # blocks re-detect for hours on SIGKILL.
    #
    # Defects guarded against:
    # - Thread#raise unsafety: use cooperative stop flag + short ticks.
    # - Zombie heartbeat extending NEW owner's lock: token-verified Lua EXPIRE.
    # - Indefinite extension: max_wall cap; past it, heartbeat stops refreshing.
    def self.with_user_lock_heartbeat(
      user_id, ttl: DEFAULT_TTL, heartbeat: DEFAULT_HEARTBEAT,
      max_wall: DEFAULT_MAX_WALL, timeout: DEFAULT_ACQUIRE_TIMEOUT
    )
      key = "#{NAMESPACE}:#{user_id}"
      token = SecureRandom.uuid
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      acquire!(key, token, ttl, timeout, user_id, started_at)

      stopping = false
      # Tick = min(heartbeat, HEARTBEAT_TICK). For prod (heartbeat=5min) the tick
      # is 1s — fast cooperative shutdown. For tests with sub-second heartbeats,
      # the tick shrinks to match so the lock refreshes before it expires.
      tick = [heartbeat.to_f, HEARTBEAT_TICK.to_f].min
      heartbeat_thread = Thread.new do
        elapsed_since_last = 0.0
        loop do
          sleep tick
          break if stopping

          elapsed_since_last += tick
          wall_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          # Past max_wall: stop refreshing. Lock expires on its short TTL.
          break if wall_elapsed >= max_wall.to_f

          if elapsed_since_last >= heartbeat.to_f
            Sidekiq.redis { |r| r.call('EVAL', EXPIRE_LUA, 1, key, token, ttl.to_i) }
            elapsed_since_last = 0.0
          end
        end
      rescue StandardError => e
        Rails.logger.warn(
          "event=tracks.per_user_lock_heartbeat_error user_id=#{user_id} " \
          "class=#{e.class} message=#{e.message}"
        )
      end

      begin
        yield
      ensure
        stopping = true
        heartbeat_thread.join([tick * 3, 1.0].max)
        release(key, token)
      end
    end

    # Force-clears a per-user lock without owning the token. Use only from
    # operator/support paths; bypasses the token-verified guard.
    def self.force_clear(user_id)
      key = "#{NAMESPACE}:#{user_id}"
      Sidekiq.redis { |r| r.del(key) }
    end
  end
end
