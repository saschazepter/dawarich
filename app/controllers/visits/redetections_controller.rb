# frozen_string_literal: true

class Visits::RedetectionsController < ApplicationController
  before_action :authenticate_user!

  COOLDOWN = 1.hour

  def create
    if cooldown_active?
      respond_to do |format|
        format.html do
          redirect_to settings_visit_detection_path,
                      alert: 'Re-detect ran recently. Try again in an hour.',
                      status: :too_many_requests
        end
        format.json { render json: { error: 'cooldown_active' }, status: :too_many_requests }
      end
      return
    end

    Visits::FullHistoryRedetectJob.perform_later(current_user.id)
    redirect_to settings_visit_detection_path,
                notice: "Re-detection queued. We'll notify you when it finishes."
  end

  private

  def cooldown_active?
    last = current_user.visits_redetected_at
    last.present? && last > COOLDOWN.ago
  end
end
