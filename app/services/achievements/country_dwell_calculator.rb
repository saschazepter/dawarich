# frozen_string_literal: true

module Achievements
  class CountryDwellCalculator
    PAIR_CAP_SECONDS = 30.minutes.to_i
    COVERAGE_THRESHOLD = 0.9

    SQL = <<~SQL
      WITH pts AS (
        SELECT p."timestamp" AS ts,
               c.iso_a2 AS code,
               LEAD(p."timestamp") OVER (ORDER BY p."timestamp", p.id) AS next_ts,
               LEAD(c.iso_a2) OVER (ORDER BY p."timestamp", p.id) AS next_code
        FROM points p
        LEFT JOIN countries c ON c.id = p.country_id
        WHERE p.user_id = %<user_id>d
          AND p."timestamp" >= %<since>d
          AND p.lonlat IS NOT NULL
          AND (p.anomaly IS DISTINCT FROM TRUE)
      )
      SELECT code, SUM(LEAST(next_ts - ts, %<cap>d))::bigint
      FROM pts
      WHERE code IS NOT NULL AND code = next_code AND next_ts > ts
      GROUP BY code
    SQL

    COVERAGE_SQL = <<~SQL
      SELECT COUNT(*) FILTER (WHERE country_id IS NOT NULL)::float / NULLIF(COUNT(*), 0)
      FROM points
      WHERE user_id = %<user_id>d
        AND "timestamp" >= %<since>d
        AND lonlat IS NOT NULL
        AND (anomaly IS DISTINCT FROM TRUE)
    SQL

    def initialize(user, since: 0)
      @user = user
      @since = since
    end

    def call
      return spatial_fallback unless country_ids_populated?

      ApplicationRecord.connection.select_rows(sql).to_h { |code, dwell| [code, dwell.to_i] }
    end

    private

    def sql
      format(SQL, user_id: @user.id, since: @since, cap: PAIR_CAP_SECONDS)
    end

    def country_ids_populated?
      coverage = ApplicationRecord.connection.select_value(
        format(COVERAGE_SQL, user_id: @user.id, since: @since)
      )

      coverage.nil? || coverage.to_f >= COVERAGE_THRESHOLD
    end

    def spatial_fallback
      Rails.logger.info(
        "Achievements: country_id coverage below #{COVERAGE_THRESHOLD} for user #{@user.id}, " \
        'falling back to the spatial path'
      )

      GridDwellCalculator.new(@user, table: 'countries', since: @since).call
    end
  end
end
