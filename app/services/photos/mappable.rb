# frozen_string_literal: true

class Photos::Mappable
  MAX_PHOTOS = 100

  def initialize(photos, privacy_zones: [], max: MAX_PHOTOS)
    @photos = photos
    @privacy_zones = privacy_zones
    @max = max
  end

  def call
    @photos.select { |p| p[:latitude].present? && p[:longitude].present? }
           .reject { |p| within_privacy_zone?(p[:latitude], p[:longitude]) }
           .first(@max)
  end

  private

  def within_privacy_zone?(lat, lon)
    return false if lat.blank? || lon.blank?

    @privacy_zones.any? do |zone|
      haversine_meters(lat.to_f, lon.to_f, zone[:lat], zone[:lon]) <= zone[:radius]
    end
  end

  def haversine_meters(lat1, lon1, lat2, lon2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlon = (lon2 - lon1) * rad
    a = (Math.sin(dlat / 2)**2) +
        (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlon / 2)**2))
    6_371_000 * 2 * Math.asin(Math.sqrt(a))
  end
end
