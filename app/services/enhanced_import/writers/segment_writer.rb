# frozen_string_literal: true

module EnhancedImport
  module Writers
    class SegmentWriter
      def upsert(track, extracted)
        return nil if track.nil?

        existing = TrackSegment.find_by(track_id: track.id, start_index: extracted.start_index)
        return [existing, false] if existing

        segment = track.track_segments.create!(
          start_index: extracted.start_index,
          end_index: extracted.end_index,
          transportation_mode: extracted.transportation_mode,
          confidence: confidence_level(extracted.confidence),
          source: extracted.source_label
        )
        [segment, true]
      rescue ActiveRecord::RecordNotUnique
        existing = TrackSegment.find_by(track_id: track.id, start_index: extracted.start_index)
        [existing, false]
      end

      private

      def confidence_level(value)
        return :low if value.nil?

        numeric = value.to_f
        return :high if numeric >= 0.8 && numeric <= 1.0
        return :high if numeric >= 80
        return :medium if numeric >= 0.5 && numeric < 0.8
        return :medium if numeric >= 50

        :low
      end
    end
  end
end
