# frozen_string_literal: true

class Visits::RealtimeDebouncer
  DEBOUNCE_DELAY = 5.minutes
  REDIS_KEY_TTL = 10.minutes
  LOOKBACK_WINDOW = 25.hours
  OPTIN_CACHE_TTL = 5.minutes

  def self.bust_optin_cache(user_id)
    Sidekiq.redis { |r| r.del("visit_optin:user:#{user_id}") }
  end

  def initialize(user_id)
    @user_id = user_id
  end

  def trigger
    # Realtime detection runs regardless of reverse-geocoding availability;
    # missing geodata degrades gracefully to Place::DEFAULT_NAME.
    return unless user_opted_in?

    redis_pool.with do |redis|
      key = redis_key
      if redis.set(key, 1, nx: true, ex: REDIS_KEY_TTL.to_i)
        begin
          VisitSuggestingJob
            .set(wait: DEBOUNCE_DELAY)
            .perform_later(
              user_id: @user_id,
              start_at: LOOKBACK_WINDOW.ago.iso8601,
              end_at: Time.current.iso8601,
              realtime: true
            )
        rescue StandardError
          redis.del(key)
          raise
        end
      else
        redis.expire(key, REDIS_KEY_TTL.to_i)
      end
    end
  end

  def clear
    redis_pool.with { |redis| redis.del(redis_key) }
  end

  private

  def user_opted_in?
    cached = redis_pool.with { |r| r.get(optin_cache_key) }
    return cached == '1' unless cached.nil?

    enabled = User.find_by(id: @user_id)&.safe_settings&.visits_suggestions_enabled? ? true : false
    redis_pool.with { |r| r.set(optin_cache_key, enabled ? '1' : '0', ex: OPTIN_CACHE_TTL.to_i) }
    enabled
  end

  def optin_cache_key
    "visit_optin:user:#{@user_id}"
  end

  def redis_key
    "visit_realtime:user:#{@user_id}"
  end

  def redis_pool
    Sidekiq.redis_pool
  end
end
