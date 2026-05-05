# frozen_string_literal: true

class VideosController < ApplicationController
  include ActiveStorage::SetCurrent
  include FlashStreamable

  before_action :authenticate_user!
  before_action :require_video_service
  before_action :require_pro
  before_action :set_video, only: %i[destroy]

  def index
    @videos = current_user.videos.with_attached_file
                          .order(created_at: :desc)
                          .limit(50)
  end

  def create
    @video = build_video_from_params
    return head :not_found if @video.nil?

    if @video.save
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:success, 'Video queued — check the Videos page.')
        end
        format.html { redirect_to videos_path, notice: 'Video queued.' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:error, @video.errors.full_messages.to_sentence)
        end
        format.html { redirect_to videos_path, alert: @video.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @video.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to videos_path, status: :see_other, notice: 'Video deleted.' }
    end
  end

  private

  def set_video
    @video = current_user.videos.find(params[:id])
  end

  def build_video_from_params
    if params[:track_id].present?
      track = current_user.tracks.find_by(id: params[:track_id])
      return nil unless track

      current_user.videos.new(track:, start_at: track.start_at, end_at: track.end_at)
    elsif params[:date].present?
      date = Date.parse(params[:date])
      tz   = current_user.try(:timezone) || Time.zone.name
      current_user.videos.new(
        track: nil,
        start_at: date.in_time_zone(tz).beginning_of_day,
        end_at: date.in_time_zone(tz).end_of_day
      )
    end
  rescue ArgumentError
    nil
  end

  def require_video_service
    return if DawarichSettings.video_service_enabled?

    redirect_to root_path, alert: 'Video service is not available.'
  end

  def require_pro
    return unless current_user.plan_restricted?

    redirect_to root_path, alert: 'Video export is a Pro feature.'
  end
end
