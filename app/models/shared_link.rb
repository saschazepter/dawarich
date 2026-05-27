# frozen_string_literal: true

class SharedLink < ApplicationRecord
  RESOURCE_TYPES_REQUIRING_ID = %w[trip track].freeze

  belongs_to :user
  has_one_attached :og_image

  enum :resource_type, { trip: 0, track: 1, timeline: 2, live: 3 }
  enum :og_image_state, { pending: 0, ready: 1, failed: 2 }, prefix: :og_image

  validates :name, presence: true, length: { maximum: 255 }
  validates :magic_phrase, length: { maximum: 255 }, allow_nil: true
  validate :resource_id_matches_type

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
end
