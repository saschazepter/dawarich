# frozen_string_literal: true

class Shared::AchievementsController < ApplicationController
  def show
    progress = AchievementProgress.find_by(sharing_uuid: params[:uuid], sharing_enabled: true)
    definition = progress && Achievements::Registry.find(progress.achievement_key)

    if progress.nil? || definition.nil?
      return redirect_to root_path, alert: 'Shared achievement not found or no longer available'
    end

    @set = Achievements::SetPresenter.new(definition: definition, progress: progress)
  end
end
