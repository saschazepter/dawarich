# frozen_string_literal: true

class Api::V1::VideosController < ApiController
  include ActiveStorage::SetCurrent

  skip_before_action :authenticate_api_key, only: [:callback]
  wrap_parameters false

  MAX_FILE_SIZE = 500.megabytes

  def callback
    video = Video.includes(:user).find_by(id: params[:id])
    return render json: { error: 'Unauthorized' }, status: :unauthorized unless video

    unless Videos::CallbackToken.verify(params[:token], video.id, video.callback_nonce)
      return render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    video.with_lock do
      return render json: { status: 'already_processed' }, status: :conflict if video.completed? || video.failed?

      return finish_with_file(video, params[:file]) if params[:status] == 'completed' && params[:file].present?

      finish_with_failure(video, params[:error_message].to_s)
    end

    render json: { status: 'ok' }
  end

  private

  def finish_with_file(video, file)
    detected = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
    unless detected.start_with?('video/')
      return render json: { error: 'Invalid file type' }, status: :unprocessable_content
    end
    return render json: { error: 'File too large' }, status: :unprocessable_content if file.size > MAX_FILE_SIZE
    return render json: { error: 'File is empty' }, status: :unprocessable_content if file.size.zero? # rubocop:disable Style/ZeroLengthPredicate

    video.file.attach(file)
    video.update!(status: :completed)
    Notifications::Create.new(
      user: video.user, kind: :info,
      title: 'Video ready', content: 'Your route replay video is ready for download.'
    ).call
    render json: { status: 'ok' }
  end

  def finish_with_failure(video, error_message)
    video.update!(status: :failed, error_message: error_message.truncate(500))
    Notifications::Create.new(
      user: video.user, kind: :error,
      title: 'Video failed', content: "Video render failed: #{error_message.truncate(200)}"
    ).call
  end
end
