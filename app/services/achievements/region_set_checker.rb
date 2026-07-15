# frozen_string_literal: true

module Achievements
  class RegionSetChecker
    def initialize(user, notify: true, oldest_timestamp: nil)
      @user = user
      @notify = notify
      @oldest_timestamp = oldest_timestamp
    end

    def call
      Registry.region_sets.each { |definition| check_set(definition) }
    end

    private

    attr_reader :user, :notify, :oldest_timestamp

    def check_set(definition)
      progress = Progress.find_or_create_by!(user: user, achievement_key: definition.key)
      newly_earned = []
      earned_total = 0
      completed_now = false

      progress.with_lock do
        cursor = progress.state['cursor'].to_i
        recompute = recompute?(cursor)
        result = RegionDwellCalculator.new(
          user, codes: definition.region_codes, since: recompute ? 0 : cursor
        ).call
        next if result.nil?

        state = merge_result(progress.state, result, newly_earned, replace: recompute)
        progress.update!(state: state)
        earned_total = state['earned'].size
        completed_now = award(definition) if complete?(state, definition)
      end

      send_notifications(definition, newly_earned, earned_total, completed_now)
    end

    def recompute?(cursor)
      oldest_timestamp.present? && cursor.positive? && oldest_timestamp < cursor
    end

    def merge_result(state, result, newly_earned, replace:)
      dwell = replace ? {} : state.fetch('dwell', {})
      earned = state.fetch('earned', {})

      result.deltas.each do |code, delta|
        dwell[code] = dwell.fetch(code, 0) + delta
      end

      dwell.each do |code, seconds|
        next if earned.key?(code) || seconds < threshold_seconds

        earned[code] = Time.current.iso8601
        newly_earned << code
      end

      state.merge('cursor' => result.new_cursor, 'dwell' => dwell, 'earned' => earned)
    end

    def threshold_seconds
      @threshold_seconds ||= user.safe_settings.min_minutes_spent_in_city * 60
    end

    def complete?(state, definition)
      (definition.region_codes - state['earned'].keys).empty?
    end

    def award(definition)
      achievement = UserAchievement.find_or_create_by!(user: user, achievement_key: definition.key) do |ua|
        ua.earned_at = Time.current
      end

      achievement.previously_new_record?
    end

    def send_notifications(definition, newly_earned, earned_total, completed_now)
      return unless notify

      newly_earned.each do |code|
        ::Notifications::Create.new(
          user: user, kind: :info,
          title: "#{definition.regions[code]} explored!",
          content: "#{definition.name}: #{earned_total}/#{definition.total} regions visited."
        ).call
      end

      return unless completed_now

      ::Notifications::Create.new(
        user: user, kind: :info,
        title: "#{definition.name} completed!",
        content: "You explored all #{definition.total} regions."
      ).call
    end
  end
end
