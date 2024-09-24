# frozen_string_literal: true

class GoogleMaps::SemanticHistoryParser
  attr_reader :import, :user_id

  def initialize(import, user_id)
    @import = import
    @user_id = user_id
  end

  def call
    points_data = parse_json

    points_data.each do |point_data|
      next if Point.exists?(
        timestamp: point_data[:timestamp],
        latitude: point_data[:latitude],
        longitude: point_data[:longitude],
        user_id:
      )

      Point.create(
        latitude: point_data[:latitude],
        longitude: point_data[:longitude],
        timestamp: point_data[:timestamp],
        raw_data: point_data[:raw_data],
        topic: 'Google Maps Timeline Export',
        tracker_id: 'google-maps-timeline-export',
        import_id: import.id,
        user_id:
      )
    end
  end

  private

  def parse_json
    import.raw_data['timelineObjects'].flat_map do |timeline_object|
      if timeline_object['activitySegment'].present?
        if timeline_object['activitySegment']['startLocation'].blank?
          next if timeline_object['activitySegment']['waypointPath'].blank?

          timeline_object['activitySegment']['waypointPath']['waypoints'].map do |waypoint|
            {
              latitude: waypoint['latE7'].to_f / 10**7,
              longitude: waypoint['lngE7'].to_f / 10**7,
              timestamp: parse_timestamp(timeline_object['activitySegment']['duration']['startTimestamp'] || timeline_object['activitySegment']['duration']['startTimestampMs']),
              raw_data: timeline_object
            }
          end
        else
          {
            latitude: timeline_object['activitySegment']['startLocation']['latitudeE7'].to_f / 10**7,
            longitude: timeline_object['activitySegment']['startLocation']['longitudeE7'].to_f / 10**7,
            timestamp: parse_timestamp(timeline_object['activitySegment']['duration']['startTimestamp'] || timeline_object['activitySegment']['duration']['startTimestampMs']),
            raw_data: timeline_object
          }
        end
      elsif timeline_object['placeVisit'].present?
        if timeline_object['placeVisit']['location']['latitudeE7'].present? &&
           timeline_object['placeVisit']['location']['longitudeE7'].present?
          {
            latitude: timeline_object['placeVisit']['location']['latitudeE7'].to_f / 10**7,
            longitude: timeline_object['placeVisit']['location']['longitudeE7'].to_f / 10**7,
            timestamp: parse_timestamp(timeline_object['placeVisit']['duration']['startTimestamp'] || timeline_object['placeVisit']['duration']['startTimestampMs']),
            raw_data: timeline_object
          }
        elsif timeline_object['placeVisit']['otherCandidateLocations'].any?
          point = timeline_object['placeVisit']['otherCandidateLocations'][0]

          next unless point['latitudeE7'].present? && point['longitudeE7'].present?

          {
            latitude: point['latitudeE7'].to_f / 10**7,
            longitude: point['longitudeE7'].to_f / 10**7,
            timestamp: parse_timestamp(timeline_object['placeVisit']['duration']['startTimestamp'] || timeline_object['placeVisit']['duration']['startTimestampMs']),
            raw_data: timeline_object
          }
        else
          next
        end
      end
    end.reject(&:blank?)
  end

  def parse_timestamp(timestamp)
    begin
	    # Falls der Zeitstempel im ISO 8601-Format vorliegt, versuche, ihn zu parsen
      DateTime.parse(timestamp).to_time.to_i
	  rescue
      if timestamp.to_s.length > 10
        # Falls der Zeitstempel in Millisekunden vorliegt, konvertiere ihn in Sekunden
        timestamp.to_i / 1000
      else
        # Falls der Zeitstempel in Sekunden vorliegt, gebe ihn unverändert zurück
        timestamp.to_i
	    end
    end
  end
end
