# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CountriesAndCities do
  describe '#call with empty geodata (regression #2732)' do
    let(:timestamp) { DateTime.new(2021, 1, 1, 0, 0, 0) }

    let(:points) do
      (0..6).map do |i|
        create(:point, city: 'Berlin', country: 'Germany', timestamp: timestamp + (i * 10).minutes)
          .tap { |point| point.update_columns(country_name: nil, geodata: {}) }
      end
    end

    it 'counts the country from country_id and the city from the column' do
      result = described_class.new(points, min_minutes_spent_in_city: 5).call

      expect(result.map(&:country)).to eq(['Germany'])
      expect(result.first.cities.map(&:city)).to eq(['Berlin'])
    end
  end
end
