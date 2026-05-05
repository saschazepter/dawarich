# frozen_string_literal: true

class VideoJob < ApplicationJob
  queue_as :videos

  def perform(video_id)
    video = Video.find(video_id)
    video.update!(status: :processing)
    Videos::RequestRender.new(video:).call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.info("[VideoJob] Video #{video_id} missing, skipping")
  rescue StandardError => e
    Video.where(id: video_id).update_all(
      status: Video.statuses[:failed],
      error_message: e.message.to_s.truncate(500),
      updated_at: Time.current
    )
    ExceptionReporter.call(e)
  end
end
