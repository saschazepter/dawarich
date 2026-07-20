# frozen_string_literal: true

class AchievementsController < ApplicationController
  ROWS_PER_PAGE = 10

  before_action :authenticate_user!
  before_action :require_feature_enabled
  before_action :load_exploration, only: %i[index show]

  def index
    @sets = @continents
    mark_celebrated(@continents + @orphans + @tiers)
  end

  def show
    definition = Achievements::Registry.find(params[:key])
    raise ActiveRecord::RecordNotFound if definition.nil?
    raise ActiveRecord::RecordNotFound if definition.flat? && definition.parent_key.nil?
    return redirect_to achievement_path(definition.parent_key) if definition.flat?

    @set = presenters_for([definition]).first
    @sidebar_key = definition.parent_key || definition.key
    @children = paginate(@set.compact? ? @set.region_rows : @set.region_cards)

    mark_celebrated([@set])
  end

  def toggle_sharing
    raise ActiveRecord::RecordNotFound unless Achievements::Registry.find(params[:key])

    progress = current_user.achievement_progresses.find_or_create_by!(achievement_key: params[:key])
    progress.update!(
      sharing_enabled: !progress.sharing_enabled,
      sharing_uuid: progress.sharing_uuid || SecureRandom.uuid
    )

    redirect_to achievements_path
  end

  private

  def load_exploration
    @exploration = Achievements::Progress.exploration_for(current_user)
    @state = @exploration.state
    @carriers = current_user.achievement_progresses
                            .where.not(achievement_key: Achievements::Progress::EXPLORATION_KEY)
                            .index_by(&:achievement_key)

    by_kind = Achievements::Registry.all.group_by(&:kind)
    @continents = presenters_for(by_kind.fetch('continent', []))
    @tiers = presenters_for(by_kind.fetch('region_set', []))
    @orphans = presenters_for(by_kind.fetch('country', []).select { |set| set.parent_key.nil? })
    @world = Achievements::WorldStagesPresenter.new(state: @state)
    @summary = Achievements::SummaryPresenter.new(state: @state)
  end

  def presenters_for(definitions)
    definitions.map do |definition|
      Achievements::SetPresenter.new(
        definition: definition, state: @state, sharing: @carriers[definition.key]
      )
    end
  end

  def paginate(collection)
    Kaminari.paginate_array(collection).page(params[:page]).per(ROWS_PER_PAGE)
  end

  def mark_celebrated(sets)
    keys = sets.select(&:celebrate?).map { |set| set.definition.key }
    return if keys.empty? || !@exploration.persisted?

    @exploration.with_lock do
      celebrated = @exploration.state.fetch('celebrated', {})
      keys.each { |key| celebrated[key] = Time.current.iso8601 }
      @exploration.update!(state: @exploration.state.merge('celebrated' => celebrated))
    end
  end

  def require_feature_enabled
    redirect_to root_path unless Flipper.enabled?(:achievements)
  end
end
