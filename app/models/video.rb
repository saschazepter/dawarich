# frozen_string_literal: true

class Video < ApplicationRecord
  belongs_to :user
  belongs_to :track, optional: true

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3 }

  has_one_attached :file

  validates :start_at, :end_at, presence: true
  validates :name, length: { maximum: 200 }
  validate :end_at_after_start_at
  validate :track_belongs_to_user, if: -> { track_id.present? && track_id_changed? }

  before_validation :generate_callback_nonce, on: :create
  before_save :set_processing_started_at, if: :status_changed_to_processing?

  after_commit -> { VideoJob.perform_later(id) }, on: :create
  after_commit -> { file.purge_later }, on: :destroy
  after_commit :broadcast_status, on: %i[create update], if: :saved_change_to_status?

  def display_name
    return name if name.present?

    "#{start_at&.strftime('%Y-%m-%d')} — #{end_at&.strftime('%Y-%m-%d')}"
  end

  def download_filename
    base = "route-#{start_at&.strftime('%Y-%m-%d')}"
    "#{base.parameterize}.mp4"
  end

  private

  def generate_callback_nonce
    self.callback_nonce ||= SecureRandom.urlsafe_base64(32)
  end

  def set_processing_started_at
    self.processing_started_at = Time.current
  end

  def status_changed_to_processing?
    will_save_change_to_status? && processing?
  end

  def end_at_after_start_at
    return unless start_at && end_at

    errors.add(:end_at, 'must be after start date') if end_at <= start_at
  end

  def track_belongs_to_user
    return if user&.tracks&.exists?(id: track_id)

    errors.add(:track_id, 'does not belong to this user')
  end

  def broadcast_status
    html = ApplicationController.renderer.render(partial: 'videos/video', locals: { video: self })
    VideosChannel.broadcast_to(user, { id: ActionView::RecordIdentifier.dom_id(self), html: html })
  end
end
