# frozen_string_literal: true

class SharedLink < ApplicationRecord
  RESOURCE_TYPES_REQUIRING_ID = %w[trip track].freeze

  belongs_to :user
  has_one_attached :og_image

  enum :resource_type, { trip: 0, track: 1, timeline: 2, live: 3 }
  enum :og_image_state, { pending: 0, ready: 1, failed: 2 }, prefix: :og_image

  DEFAULT_SETTINGS = {
    trip: {
      'show_photos' => false, 'show_places' => true, 'show_addresses' => false, 'show_stats' => true
    }.freeze,
    track: {
      'show_photos' => false, 'show_places' => false, 'show_addresses' => false, 'show_stats' => true
    }.freeze,
    timeline: {
      'show_photos' => false, 'show_places' => true, 'show_addresses' => false
    }.freeze,
    live: {
      'show_photos' => false, 'show_places' => false, 'show_addresses' => false, 'history_hours' => 6
    }.freeze
  }.freeze

  def self.default_settings_for(resource_type)
    DEFAULT_SETTINGS.fetch(resource_type.to_sym).dup
  end

  validates :name, presence: true, length: { maximum: 255 }
  validates :magic_phrase, length: { maximum: 255 }, allow_nil: true
  validate :resource_id_matches_type
  validate :timeline_dates_present_and_ordered

  scope :active, lambda {
    where(revoked_at: nil)
      .where('expires_at IS NULL OR expires_at > ?', Time.current)
  }

  def resource
    case resource_type.to_sym
    when :trip     then user.trips.find_by(id: resource_id)
    when :track    then user.tracks.find_by(id: resource_id)
    when :timeline then nil
    when :live     then user
    end
  end

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at > Time.current)
  end

  def touch_access!
    update!(view_count: view_count + 1, last_accessed_at: Time.current)
  end

  private

  def resource_id_matches_type
    needs_id = RESOURCE_TYPES_REQUIRING_ID.include?(resource_type)
    if needs_id && resource_id.blank?
      errors.add(:resource_id, 'is required for this resource type')
    elsif !needs_id && resource_id.present?
      errors.add(:resource_id, 'must be blank for this resource type')
    end
  end

  def timeline_dates_present_and_ordered
    return unless timeline?

    start_date = settings['start_date'].presence
    end_date   = settings['end_date'].presence

    if start_date.blank? || end_date.blank?
      errors.add(:settings, 'must include start_date and end_date for timeline shares')
      return
    end

    parsed_start = safe_parse_date(start_date)
    parsed_end   = safe_parse_date(end_date)

    if parsed_start.nil? || parsed_end.nil?
      errors.add(:settings, 'start_date and end_date must be parseable as dates')
      return
    end

    errors.add(:settings, 'end_date must be on or after start_date') if parsed_end < parsed_start
  end

  def safe_parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
