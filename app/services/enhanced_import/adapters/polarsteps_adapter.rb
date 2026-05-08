# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class PolarstepsAdapter < BaseAdapter
      SOURCE_LABEL = 'polarsteps'

      def translate
        return enum_for(:translate) unless block_given?

        json = load_json_data
        Array(json['steps']).each do |step|
          visit = build_visit(step)
          yield visit if visit
        end
      end

      private

      def build_visit(step)
        location = step['location']
        return nil if location.blank?

        latitude  = location['lat']&.to_f
        longitude = location['lon']&.to_f
        return nil if latitude.nil? || longitude.nil?

        started_at = parse_unix(step['start_time'])
        ended_at   = parse_unix(step['end_time'])
        return nil if started_at.nil? || ended_at.nil?

        place_name = step['display_name'].presence || step['name'].presence || location['detail'].presence || 'Unknown'

        place = Extracted::Place.new(
          external_place_id: "polarsteps:#{step['id']}",
          name: place_name,
          latitude: latitude,
          longitude: longitude,
          semantic_type: 'polarsteps_step'
        )

        Extracted::Visit.new(
          started_at: started_at,
          ended_at: ended_at,
          place: place,
          name: place_name,
          confidence: nil,
          source_label: SOURCE_LABEL
        )
      end

      def parse_unix(value)
        return nil if value.blank?

        Time.zone.at(value.to_i)
      end
    end
  end
end
