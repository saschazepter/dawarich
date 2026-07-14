# frozen_string_literal: true

class Points::Create
  UPSERT_MAX_RETRIES = 3

  attr_reader :user, :params

  def initialize(user, params)
    @user = user
    @params = params.to_h
  end

  def call
    data = Points::Params.new(params, user.id).call

    deduplicated_data = data.uniq { |point| Point.dedup_key(point) }

    created_points = []
    inserted_count = 0

    deduplicated_data.each_slice(1000) do |location_batch|
      result = with_upsert_retry do
        Point.archival_safe_upsert_all(
          location_batch,
          returning: Arel.sql(
            'id, xmax, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude'
          )
        )
      end
      inserted_count += result.count { |row| row['xmax'].to_i.zero? }
      created_points.concat(result)
    end

    if created_points.any?
      User.update_counters(user.id, points_count: inserted_count) if inserted_count.positive?
      timestamps = deduplicated_data.filter_map { |p| p[:timestamp]&.to_i }
      Points::AnomalyFilterJob.perform_later(user.id, timestamps.min, timestamps.max) if timestamps.any?
      Tracks::RealtimeDebouncer.new(user.id).trigger
      Tracks::BackfillScheduler.new(user.id, timestamps).call
      Visits::RealtimeDebouncer.new(user.id).trigger
      Points::LiveBroadcaster.new(user.id, created_points, deduplicated_data).call
    end

    created_points
  end

  private

  def with_upsert_retry
    retries = 0

    begin
      yield
    rescue ActiveRecord::Deadlocked => e
      retries += 1
      raise e if retries > UPSERT_MAX_RETRIES

      sleep(0.1 * retries)
      retry
    end
  end
end
