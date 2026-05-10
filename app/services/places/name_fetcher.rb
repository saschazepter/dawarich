# frozen_string_literal: true

module Places
  class NameFetcher
    def initialize(place)
      @place = place
    end

    def call
      geodata = Geocoder.search([place.lat, place.lon], units: :km, limit: 1, distance_sort: true).first

      return if geodata.blank?

      properties = geodata.data&.dig('properties')
      return if properties.blank?

      ActiveRecord::Base.transaction do
        update_place_name(properties, geodata)
        update_visits_name(properties)

        place
      end
    rescue StandardError => e
      Rails.logger.error("Geocoding error in NameFetcher for place #{place.id}: #{e.message}")
      ExceptionReporter.call(e)
      nil
    end

    private

    attr_reader :place

    def update_place_name(properties, geodata)
      built_name = ::Visits::Names::Builder.build_from_properties(properties)
      place.name = built_name if built_name.present?
      place.city = properties['city'] if properties['city'].present?
      place.country = properties['country'] if properties['country'].present?
      place.geodata = geodata.data if DawarichSettings.store_geodata?

      place.save!
    end

    def update_visits_name(properties)
      built_name = ::Visits::Names::Builder.build_from_properties(properties)
      return if built_name.blank?

      place.visits.where(name: Place::DEFAULT_NAME).update_all(name: built_name)
    end
  end
end
