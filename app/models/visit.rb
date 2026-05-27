# frozen_string_literal: true

class Visit < ApplicationRecord
  belongs_to :area, optional: true
  belongs_to :place, optional: true
  belongs_to :user
  has_many :points, dependent: :nullify
  has_many :place_visits, dependent: :destroy
  has_many :suggested_places, through: :place_visits, source: :place

  after_commit :cleanup_old_place_if_orphan, on: :update
  after_destroy_commit :cleanup_place_if_orphan

  validates :started_at, :ended_at, :duration, :name, :status, presence: true

  validates :ended_at, comparison: { greater_than: :started_at }

  enum :status, { suggested: 0, confirmed: 1, declined: 2 }

  # "Same place" threshold used by Visits::Creator#find_existing_visit to dedup
  # newly-clustered visits against existing ones at the same centroid. Distinct
  # from PlaceFinder::SIMILARITY_RADIUS (50m, place-level) and
  # Merger::SIGNIFICANT_MOVEMENT_THRESHOLD (50m, between-visits movement).
  SAME_PLACE_METERS = 100

  def coordinates
    # Read lat/lon from the lonlat geography column (source of truth). The
    # decimal latitude/longitude columns are nil in production data, so the
    # old `points.pluck(:latitude, :longitude)` returned nil pairs.
    points.map { |p| [p.lat, p.lon] }
  end

  def default_name
    name || area&.name || place&.name
  end

  MIN_DEFAULT_RADIUS_METERS = 15

  # Always in metres. View layer converts to user's preferred unit when needed.
  def default_radius
    return area&.radius if area.present?

    distances_in_meters = points.map do |point|
      Geocoder::Calculations.distance_between(
        center, [point.lat, point.lon], units: :km
      ) * 1000
    end
    max_meters = distances_in_meters.max
    max_meters && max_meters >= MIN_DEFAULT_RADIUS_METERS ? max_meters : MIN_DEFAULT_RADIUS_METERS
  end

  def center
    if area.present?
      [area.lat, area.lon]
    elsif place.present?
      [place.lat, place.lon]
    else
      center_from_points
    end
  end

  private

  def center_from_points
    return [0, 0] if points.empty?

    lat_sum = points.sum(&:lat)
    lon_sum = points.sum(&:lon)
    count = points.size.to_f

    [lat_sum / count, lon_sum / count]
  end

  def cleanup_old_place_if_orphan
    old_id, = previous_changes['place_id']
    return unless old_id

    Places::DeleteIfOrphanJob.perform_later(old_id)
  end

  def cleanup_place_if_orphan
    return unless place_id

    Places::DeleteIfOrphanJob.perform_later(place_id)
  end
end
