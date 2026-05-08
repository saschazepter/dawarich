# frozen_string_literal: true

# Advisory lock namespace registry — DO NOT REUSE: 4242 = Tracks::PerUserLock.
module Tracks
  module PerUserLock
    LOCK_NAMESPACE = 4242

    def self.with_user_lock(user_id)
      conn = ActiveRecord::Base.connection
      conn.execute(acquire_sql(user_id))
      yield
    ensure
      conn.execute(release_sql(user_id)) if conn
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
