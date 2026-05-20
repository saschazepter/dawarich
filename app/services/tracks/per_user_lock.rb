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

    class AcquisitionTimeout < StandardError; end

    def self.with_user_lock(user_id, timeout: DEFAULT_ACQUIRE_TIMEOUT, ttl: DEFAULT_TTL)
      key = "#{NAMESPACE}:#{user_id}"
      token = SecureRandom.uuid
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      acquire!(key, token, ttl, timeout, user_id, started_at)

      begin
        yield
      ensure
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
  end
end
