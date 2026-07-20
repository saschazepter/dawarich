# frozen_string_literal: true

module Achievements
  class SummaryPresenter
    def initialize(state:)
      @state = state || {}
    end

    def earned_countries
      @earned_countries ||= (earned_codes & country_codes).size
    end

    def total_countries
      @total_countries ||= country_codes.size
    end

    def earned_subdivisions
      @earned_subdivisions ||= (earned_codes & subdivision_codes).size
    end

    def total_subdivisions
      @total_subdivisions ||= subdivision_codes.size
    end

    def percent
      return 0 if total_countries.zero?

      (earned_countries * 100.0 / total_countries).round
    end

    private

    attr_reader :state

    def earned_codes
      @earned_codes ||= state.fetch('earned', {}).keys.to_set
    end

    def country_codes
      @country_codes ||= Registry.all
                                 .select { |definition| definition.kind == 'country' }
                                 .map(&:country).to_set
    end

    def subdivision_codes
      @subdivision_codes ||= Registry.subdivision_sets.flat_map(&:region_codes).to_set
    end
  end
end
