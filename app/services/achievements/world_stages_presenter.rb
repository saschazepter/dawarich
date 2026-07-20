# frozen_string_literal: true

module Achievements
  class WorldStagesPresenter
    KEYS = %w[border_hopper globetrotter world_traveler].freeze

    def initialize(state:)
      @state = state || {}
    end

    def stages
      @stages ||= presenters.map do |presenter|
        {
          name: presenter.definition.name,
          rarity: presenter.rarity,
          threshold: presenter.target,
          reached: presenter.completed?,
          reached_on: presenter.completed_on
        }
      end
    end

    def earned_count
      presenters.first.earned_count
    end

    def reached
      stages.select { |stage| stage[:reached] }
    end

    def next_stage
      stages.find { |stage| !stage[:reached] }
    end

    def rarity
      reached.last&.fetch(:rarity) || 'Common'
    end

    def target
      next_stage ? next_stage[:threshold] : stages.last[:threshold]
    end

    def percent
      return 100 if next_stage.nil?

      [(earned_count * 100.0 / next_stage[:threshold]).round, 100].min
    end

    def completed?
      next_stage.nil?
    end

    def locked?
      earned_count.zero?
    end

    def celebrate?
      presenters.any?(&:celebrate?)
    end

    def earned_label
      return 'Locked' if locked?
      return reached.last[:name] if completed?

      "#{earned_count} of #{next_stage[:threshold]} countries"
    end

    def card_attributes
      art = definition.card['art']

      {
        name: 'World Explorer',
        description: description,
        flavor: definition.card['flavor'],
        rarity: rarity,
        place: 'The World',
        map_lat: art['lat'], map_lon: art['lon'], map_zoom: art['zoom'],
        marker_lat: art['lat'], marker_lon: art['lon'],
        percent: percent, completed: completed?, locked: locked?,
        earned_label: earned_label
      }
    end

    private

    attr_reader :state

    def description
      return "Visited #{earned_count} countries — every milestone cleared." if completed?

      "Spend time in #{next_stage[:threshold]} different countries."
    end

    def definition
      @definition ||= Registry.find(KEYS.first)
    end

    def presenters
      @presenters ||= KEYS.map { |key| SetPresenter.new(definition: Registry.find(key), state: state) }
    end
  end
end
