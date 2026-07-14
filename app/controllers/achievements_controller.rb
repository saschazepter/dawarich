# frozen_string_literal: true

class AchievementsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_feature_enabled

  def index
    @sets = Achievements::Registry.region_sets.map do |definition|
      Achievements::SetPresenter.new(
        definition: definition,
        progress: current_user.achievement_progresses.find_by(achievement_key: definition.key)
      )
    end
  end

  def toggle_sharing
    progress = current_user.achievement_progresses.find_by!(achievement_key: params[:key])
    progress.update!(
      sharing_enabled: !progress.sharing_enabled,
      sharing_uuid: progress.sharing_uuid || SecureRandom.uuid
    )

    redirect_to achievements_path
  end

  private

  def require_feature_enabled
    redirect_to root_path unless Flipper.enabled?(:achievements)
  end
end
