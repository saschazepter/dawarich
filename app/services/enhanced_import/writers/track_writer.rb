# frozen_string_literal: true

module EnhancedImport
  module Writers
    class TrackWriter
      include Tracks::TrackBuilder

      attr_reader :user

      def initialize(user, import)
        @user = user
        @import = import
      end

      def upsert(extracted, skip_segment_detection: false)
        existing = Track.where(
          user_id: user.id,
          tracker_id: extracted.tracker_id,
          start_at: extracted.start_at
        ).first
        return [existing, false] if existing

        points = matching_points(extracted)
        return [nil, false] if points.size < 2

        track = create_track_from_points(
          points,
          extracted.distance_m || 0,
          tracker_id: extracted.tracker_id,
          skip_segment_detection: skip_segment_detection
        )
        [track, true]
      rescue ActiveRecord::RecordNotUnique
        existing = Track.where(
          user_id: user.id,
          tracker_id: extracted.tracker_id,
          start_at: extracted.start_at
        ).first
        [existing, false]
      end

      private

      def matching_points(extracted)
        Point.where(
          user_id: user.id,
          import_id: @import.id,
          timestamp: extracted.start_at.to_i..extracted.end_at.to_i
        ).order(:timestamp).to_a
      end
    end
  end
end
