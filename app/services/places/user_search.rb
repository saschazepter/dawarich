# frozen_string_literal: true

module Places
  class UserSearch
    MIN_QUERY_LENGTH = 2

    # Searching by name reaches further than the proximity radius so a saved
    # place just outside the visit area is still findable by typing its name,
    # but stays bounded so a same-named place on another continent cannot
    # surface — or push the nearby suggestions out of the result set.
    NAME_SEARCH_RADIUS_KM = 50

    def initialize(user:, latitude:, longitude:, radius:, limit:, query: nil)
      @user = user
      @latitude = latitude.to_f
      @longitude = longitude.to_f
      @radius = radius.to_f
      @limit = limit.to_i
      @query = query.to_s.strip
    end

    def call
      nearby = base_scope.near([@latitude, @longitude], @radius, :km)
      scope = if @query.length >= MIN_QUERY_LENGTH
                nearby.or(named_matches_within_bounds)
              else
                nearby
              end

      scope
        .with_distance([@latitude, @longitude], :km)
        .order(:distance_in_km)
        .limit(@limit)
        .map { |place| format(place) }
    end

    private

    def base_scope
      @base_scope ||= @user.places.where.not(lonlat: nil)
    end

    def named_matches_within_bounds
      base_scope
        .near([@latitude, @longitude], [NAME_SEARCH_RADIUS_KM, @radius].max, :km)
        .where('name ILIKE ?', "%#{Place.sanitize_sql_like(@query)}%")
    end

    def format(place)
      {
        id: place.id,
        name: place.name,
        latitude: place.lat,
        longitude: place.lon,
        source: place.source
      }
    end
  end
end
