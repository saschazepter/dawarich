# frozen_string_literal: true

module NonTransactionalConcurrency
  TABLES_TO_TRUNCATE = %w[
    tracks track_segments points users imports exports stats trips areas visits
  ].freeze

  def self.truncate_all
    conn = ActiveRecord::Base.connection
    existing = conn.tables & TABLES_TO_TRUNCATE
    return if existing.empty?

    conn.execute("TRUNCATE TABLE #{existing.join(', ')} RESTART IDENTITY CASCADE")
  end
end

RSpec.configure do |config|
  config.before(:each, :non_transactional) do |example|
    self.use_transactional_tests = false

    required_threads = example.metadata[:threads] || 2
    pool_size = ActiveRecord::Base.connection_pool.size
    if pool_size < required_threads
      raise "Non-transactional spec needs pool size >= #{required_threads}, got #{pool_size}. " \
            "Set ActiveRecord pool in config/database.yml test env."
    end
  end

  config.after(:each, :non_transactional) do
    NonTransactionalConcurrency.truncate_all
  end
end
