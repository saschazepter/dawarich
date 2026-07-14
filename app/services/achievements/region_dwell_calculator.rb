# frozen_string_literal: true

module Achievements
  class RegionDwellCalculator
    PAIR_CAP_SECONDS = 30.minutes.to_i

    Result = Data.define(:deltas, :new_cursor)

    SQL = <<~SQL
      WITH pts AS (
        SELECT p."timestamp" AS ts,
               m.code,
               LEAD(p."timestamp") OVER (ORDER BY p."timestamp", p.id) AS next_ts,
               LEAD(m.code) OVER (ORDER BY p."timestamp", p.id) AS next_code
        FROM points p
        LEFT JOIN LATERAL (
          SELECT r.code
          FROM regions r
          WHERE r.code IN (:codes) AND ST_Intersects(r.geom, p.lonlat::geometry)
          ORDER BY r.code
          LIMIT 1
        ) m ON TRUE
        WHERE p.user_id = :user_id
          AND p."timestamp" >= :since
          AND p.lonlat IS NOT NULL
          AND (p.anomaly IS DISTINCT FROM TRUE)
      )
      SELECT code, SUM(LEAST(next_ts - ts, :cap))::bigint
      FROM pts
      WHERE code IS NOT NULL AND code = next_code AND next_ts > ts
      GROUP BY code
    SQL

    def initialize(user, codes:, since: 0)
      @user = user
      @codes = codes
      @since = since
    end

    def call
      new_cursor = @user.points.not_anomaly.where.not(lonlat: nil).maximum(:timestamp)
      return nil if new_cursor.nil?
      return nil if @since.positive? && new_cursor <= @since

      Result.new(deltas: dwell_deltas, new_cursor: new_cursor)
    end

    private

    def dwell_deltas
      sql = ApplicationRecord.sanitize_sql_array(
        [SQL, { user_id: @user.id, since: @since, cap: PAIR_CAP_SECONDS, codes: @codes }]
      )

      ApplicationRecord.connection.select_rows(sql).to_h { |code, dwell| [code, dwell.to_i] }
    end
  end
end
