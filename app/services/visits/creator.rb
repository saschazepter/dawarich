# frozen_string_literal: true

module Visits
  # Creates visit records from detected visit data
  class Creator
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def create_visits(visits)
      visits.map do |visit_data|
        existing_visit = find_existing_visit(visit_data)
        next nil if existing_visit

        ActiveRecord::Base.transaction do
          area = find_matching_area(visit_data)
          main_place = area ? nil : PlaceFinder.new(user).find_or_create_place(visit_data)

          visit_instance = Visit.create!(
            user: user, area: area, place: main_place,
            started_at: Time.zone.at(visit_data[:start_time]),
            ended_at:   Time.zone.at(visit_data[:end_time]),
            duration:   visit_data[:duration] / 60,
            name:       generate_visit_name(area, main_place, visit_data[:suggested_name]),
            status:     :suggested
          )

          Point.where(id: visit_data[:points].map(&:id)).update_all(visit_id: visit_instance.id)
          visit_instance
        end
      end.compact
    end

    private

    # Find if there's already a confirmed/suggested/declined visit at this location within a similar time
    def find_existing_visit(visit_data)
      # Define time window to look for existing visits (slightly wider than the visit)
      start_time = Time.zone.at(visit_data[:start_time]) - 1.hour
      end_time = Time.zone.at(visit_data[:end_time]) + 1.hour

      # Look for visits with a similar location
      user.visits
          .where(
            'started_at <= :end AND ended_at >= :start',
            start: start_time, end: end_time
          )
          .find_each do |visit|
            visit_lat, visit_lon = visit.center
            next unless visit_lat && visit_lon

            distance_meters = Geocoder::Calculations.distance_between(
              [visit_data[:center_lat], visit_data[:center_lon]],
              [visit_lat, visit_lon],
              units: :km
            ) * 1000

            return visit if distance_meters <= Visit::SAME_PLACE_METERS
      end

      nil
    end

    def find_matching_area(visit_data)
      user.areas.find do |area|
        near_area?([visit_data[:center_lat], visit_data[:center_lon]], area)
      end
    end

    def near_area?(center, area)
      distance = Geocoder::Calculations.distance_between(
        center,
        [area.latitude, area.longitude],
        units: :km
      )
      distance * 1000 <= area.radius # Convert to meters
    end

    def generate_visit_name(area, place, suggested_name)
      return area.name if area
      return place.name if place
      return suggested_name if suggested_name.present?

      'Unknown Location'
    end
  end
end
