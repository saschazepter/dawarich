# frozen_string_literal: true

module Achievements
  Definition = Data.define(:key, :kind, :name, :country, :regions) do
    def region_codes
      regions.keys
    end

    def total
      regions.size
    end
  end

  class Registry
    class << self
      def all
        @all ||= load_definitions
      end

      def region_sets
        all.select { |definition| definition.kind == 'region_set' }
      end

      def find(key)
        all.find { |definition| definition.key == key }
      end

      def reset!
        @all = nil
      end

      private

      def load_definitions
        YAML.load_file(Rails.root.join('config/achievements.yml')).map do |key, attrs|
          Definition.new(
            key: key,
            kind: attrs['kind'],
            name: attrs['name'],
            country: attrs['country'],
            regions: attrs['regions']
          )
        end
      end
    end
  end
end
