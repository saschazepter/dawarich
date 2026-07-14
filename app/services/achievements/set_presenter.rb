# frozen_string_literal: true

module Achievements
  class SetPresenter
    attr_reader :definition, :progress

    def initialize(definition:, progress:)
      @definition = definition
      @progress = progress
    end

    def earned
      progress&.state&.fetch('earned', {}) || {}
    end

    def earned_count
      earned.size
    end

    delegate :total, to: :definition

    def completed?
      earned_count == total
    end

    def regions
      definition.regions
                .map { |code, name| { code: code, name: name, earned_at: earned[code] } }
                .sort_by { |region| region[:name] }
    end

    def sharing_enabled?
      progress&.sharing_enabled || false
    end

    def sharing_uuid
      progress&.sharing_uuid
    end
  end
end
