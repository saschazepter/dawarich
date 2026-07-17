# frozen_string_literal: true

class OwnTracks::PointCreator
  RETURNING_COLUMNS = 'id, xmax, timestamp, ST_X(lonlat::geometry) AS longitude, ST_Y(lonlat::geometry) AS latitude'
  UPSERT_MAX_RETRIES = 3

  attr_reader :params, :user_id

  def initialize(params, user_id)
    @params = params
    @user_id = user_id
  end

  def call
    parsed_params = OwnTracks::Params.new(params).call
    return [] if parsed_params.blank?

    payload = parsed_params.merge(user_id:)
    return [] if payload[:timestamp].nil? || payload[:lonlat].nil?
    return [] if Points::NullIsland.lonlat?(payload[:lonlat])

    result = upsert_points([payload])
    if result.any?
      inserted_count = result.count { |row| row['xmax'].to_i.zero? }
      User.update_counters(user_id, points_count: inserted_count) if inserted_count.positive?
      timestamps = [payload].filter_map { |p| p[:timestamp]&.to_i }
      Points::AnomalyFilterJob.perform_later(user_id, timestamps.min, timestamps.max) if timestamps.any?
      Tracks::RealtimeDebouncer.new(user_id).trigger
      Tracks::BackfillScheduler.new(user_id, timestamps).call
      Visits::RealtimeDebouncer.new(user_id).trigger
      Points::LiveBroadcaster.new(user_id, result, [payload]).call
    end

    result
  end

  private

  def upsert_points(locations)
    created_points = []

    locations.each_slice(1000) do |batch|
      result = with_upsert_retry do
        Point.archival_safe_upsert_all(
          batch,
          returning: Arel.sql(RETURNING_COLUMNS)
        )
      end
      created_points.concat(result) if result
    end

    created_points
  end

  def with_upsert_retry
    retries = 0
    begin
      yield
    rescue ActiveRecord::Deadlocked, ActiveRecord::QueryCanceled => e
      retries += 1
      raise e if retries > UPSERT_MAX_RETRIES

      sleep(0.1 * retries)
      retry
    end
  end
end
