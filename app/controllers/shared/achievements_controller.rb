# frozen_string_literal: true

class Shared::AchievementsController < ApplicationController
  def show
    progress = Achievements::Progress.find_by(sharing_uuid: params[:uuid], sharing_enabled: true)
    definition = progress && Achievements::Registry.find(progress.achievement_key)

    if progress.nil? || definition.nil?
      return redirect_to root_path, alert: 'Shared achievement not found or no longer available'
    end

    exploration = Achievements::Progress.exploration_for(progress.user)

    @set = Achievements::SetPresenter.new(
      definition: definition, state: exploration.state, sharing: progress
    )
  end
end
