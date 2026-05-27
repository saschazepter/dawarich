# frozen_string_literal: true

module Memories
  # Builds the "On this day, N time ago" memory ladder for a user. For each
  # entry in LOOKBACKS, looks up the user's points on the calendar day that
  # falls exactly that long before `anchor` and returns one chapter per
  # non-empty slot. Skips slots with no geolocated points so the reel never
  # surfaces a blank memory.
  class Builder
    LOOKBACKS = [
      { key: 'months_ago_1',  label: '1 month ago',   short: '1mo', duration: 1.month,   bucket: :recent  },
      { key: 'months_ago_3',  label: '3 months ago',  short: '3mo', duration: 3.months,  bucket: :recent  },
      { key: 'months_ago_6',  label: '6 months ago',  short: '6mo', duration: 6.months,  bucket: :recent  },
      { key: 'years_ago_1',   label: '1 year ago',    short: '1y',  duration: 1.year,    bucket: :mid     },
      { key: 'years_ago_2',   label: '2 years ago',   short: '2y',  duration: 2.years,   bucket: :mid     },
      { key: 'years_ago_3',   label: '3 years ago',   short: '3y',  duration: 3.years,   bucket: :mid     },
      { key: 'years_ago_5',   label: '5 years ago',   short: '5y',  duration: 5.years,   bucket: :distant },
      { key: 'years_ago_10',  label: '10 years ago',  short: '10y', duration: 10.years,  bucket: :distant }
    ].freeze

    DEFAULT_WINDOW_DAYS = 3

    def initialize(user, anchor: Time.current, window_days: DEFAULT_WINDOW_DAYS)
      @user = user
      @anchor = anchor
      @window_days = window_days
    end

    def call
      LOOKBACKS.filter_map { |spec| build_chapter(spec) }
    end

    private

    attr_reader :user, :anchor, :window_days

    def build_chapter(spec)
      target_date = (anchor - spec[:duration]).to_date
      best_day = best_day_in_window(target_date)
      return nil unless best_day

      points = day_points(best_day)
      return nil if points.empty?

      dominant_city = dominant_city_for(points)
      return nil if dominant_city.blank?

      anchor_point = points.find { |p| p.city == dominant_city }
      cities = points.map(&:city).compact.uniq
      offset_days = (best_day - target_date).to_i

      {
        period_key: spec[:key],
        period_label: spec[:label],
        period_short: spec[:short],
        bucket: spec[:bucket],
        date: best_day.iso8601,
        date_long: best_day.strftime('%b %-d, %Y'),
        date_short: best_day.strftime('%b %-d'),
        target_date: target_date.iso8601,
        offset_days: offset_days,
        name: dominant_city,
        country: country_code_for(anchor_point),
        country_name: anchor_point.country_name,
        lat: anchor_point.latitude.to_f,
        lon: anchor_point.longitude.to_f,
        cities: cities,
        points_count: points.size,
        caption_html: caption_for(spec, dominant_city, cities, anchor_point, offset_days)
      }
    end

    # Within ±window_days of target_date, pick the day that has the most
    # geolocated points. Returns nil if the whole window is empty. Single
    # query — fetches timestamps once and bins them in Ruby.
    def best_day_in_window(target_date)
      window_start = (target_date - window_days).beginning_of_day
      window_end   = (target_date + window_days).end_of_day

      timestamps = user.points
                       .where.not(city: [nil, ''])
                       .where(timestamp: window_start.to_i..window_end.to_i)
                       .pluck(:timestamp)
      return nil if timestamps.empty?

      timestamps.group_by { |ts| Time.zone.at(ts).to_date }
                .max_by { |_date, pts| pts.size }
                &.first
    end

    def day_points(date)
      window = date.beginning_of_day..date.end_of_day
      user.points
          .where.not(city: [nil, ''])
          .where(timestamp: window.first.to_i..window.last.to_i)
          .order(:timestamp)
          .to_a
    end

    def dominant_city_for(points)
      points.each_with_object(Hash.new(0)) { |p, acc| acc[p.city] += 1 if p.city.present? }
            .max_by(&:last)
            &.first
    end

    def country_code_for(point)
      return nil if point.nil?

      Country.find_by(id: point.country_id)&.iso_a2 ||
        Country.find_by(name: point.country_name)&.iso_a2
    end

    def caption_for(spec, dominant_city, cities, point, offset_days)
      country_suffix = point&.country_name.presence ? ", #{point.country_name}" : ''
      other_cities = cities - [dominant_city]
      extra = other_cities.any? ? " You also passed through #{other_cities.join(', ')}." : ''
      offset_note = offset_note_for(offset_days)
      place = "<strong class='place'>#{dominant_city}</strong>"
      "#{spec[:label]}#{offset_note} you were in #{place}#{country_suffix}.#{extra}"
    end

    def offset_note_for(offset_days)
      return '' if offset_days.zero?

      direction = offset_days.positive? ? 'after' : 'before'
      " (#{offset_days.abs} #{'day'.pluralize(offset_days.abs)} #{direction})"
    end
  end
end
