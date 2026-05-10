# frozen_string_literal: true

class Settings::VisitDetectionController < ApplicationController
  before_action :authenticate_user!

  def show; end

  def update
    merged = current_user.safe_settings.settings.merge(settings_params.to_h)
    current_user.update!(settings: merged)

    redirect_to settings_visit_detection_path, notice: 'Visit detection settings updated'
  end

  private

  def settings_params
    params.require(:settings).permit(:visit_radius_meters, :visit_min_points, :visit_density_fill_enabled)
  end
end
