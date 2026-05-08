# frozen_string_literal: true

module EnhancedImport
  class ExtractJob < ApplicationJob
    queue_as :import

    def perform(import_id)
      import = Import.find_by(id: import_id)
      return if import.nil?

      return unless EnhancedImport::Translator.supported?(import.source)

      run(import)
    rescue ActiveRecord::RecordNotFound => e
      ExceptionReporter.call(e)
    end

    private

    def run(import)
      mark_running!(import)
      counts = process_stream(import)
      mark_completed!(import, counts)
    rescue StandardError => e
      mark_failed!(import, e)
      ExceptionReporter.call(e)
      raise
    end

    def process_stream(import)
      counts = Hash.new(0)
      user = import.user
      place_writer = Writers::PlaceWriter.new(user)
      visit_writer = Writers::VisitWriter.new(user)
      track_writer = Writers::TrackWriter.new(user, import)
      segment_writer = Writers::SegmentWriter.new

      EnhancedImport::Translator.new(import).translate do |item|
        case item
        when Extracted::Place
          place, inserted = place_writer.upsert(item)
          counts[:places] += 1 if inserted && place
        when Extracted::Visit
          place, inserted_place = place_writer.upsert(item.place)
          counts[:places] += 1 if inserted_place && place
          _, inserted_visit = visit_writer.upsert(item, place)
          counts[:visits] += 1 if inserted_visit
        when Extracted::Track
          source_segments_take_over = trust_source?(import) && item.segments.any?
          track, inserted_track = track_writer.upsert(
            item,
            skip_segment_detection: source_segments_take_over
          )
          counts[:tracks] += 1 if inserted_track && track
          if track && source_segments_take_over
            item.segments.each do |segment|
              _, inserted_segment = segment_writer.upsert(track, segment)
              counts[:segments] += 1 if inserted_segment
            end
          end
        end
      end

      counts
    end

    def trust_source?(import)
      import.additional_data_extraction.fetch('options', {}).fetch('trust_source', true)
    end

    def mark_running!(import)
      payload = import.additional_data_extraction.merge(
        'started_at' => Time.current.iso8601,
        'completed_at' => nil,
        'error_message' => nil
      )
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:running],
        additional_data_extraction: payload
      )
    end

    def mark_completed!(import, counts)
      payload = import.additional_data_extraction.merge(
        'completed_at' => Time.current.iso8601,
        'counts' => counts.transform_keys(&:to_s),
        'error_message' => nil
      )
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:completed],
        additional_data_extraction: payload
      )
    end

    def mark_failed!(import, error)
      payload = import.additional_data_extraction.merge(
        'completed_at' => Time.current.iso8601,
        'error_message' => error.message
      )
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:failed],
        additional_data_extraction: payload
      )
    end
  end
end
