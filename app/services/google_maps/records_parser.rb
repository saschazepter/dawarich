# frozen_string_literal: true

class GoogleMaps::RecordsParser
  attr_reader :import

  def initialize(import)
    @import = import
  end

  def call(json)
    data = parse_json(json)

    return if Point.exists?(
      latitude: data[:latitude],
      longitude: data[:longitude],
      timestamp: data[:timestamp],
      user_id: import.user_id
    )

    Point.create(
      latitude: data[:latitude],
      longitude: data[:longitude],
      timestamp: data[:timestamp],
      raw_data: data[:raw_data],
      topic: 'Google Maps Timeline Export',
      tracker_id: 'google-maps-timeline-export',
      import_id: import.id,
      user_id: import.user_id
    )
  end

  private

  def parse_json(json)
    {
      latitude: json['latitudeE7'].to_f / 10**7,
      longitude: json['longitudeE7'].to_f / 10**7,
      timestamp: parse_timestamp(json['timestamp'] || json['timestampMs']),
      altitude: json['altitude'],
      velocity: json['velocity'],
      raw_data: json
    }
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
