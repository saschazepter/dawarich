# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CountriesAndCities do
  describe '#call with geodata fallback' do
    let(:timestamp) { DateTime.new(2021, 1, 1, 0, 0, 0).to_i }

    def geodata_for(city, country)
      {
        'type' => 'Feature',
        'properties' => { 'city' => city, 'country' => country }
      }
    end

    let(:points) do
      (0..6).map do |i|
        create(
          :point,
          city: nil,
          country_name: nil,
          country_id: nil,
          timestamp: timestamp + (i * 10).minutes,
          geodata: geodata_for('Berlin', 'Germany')
        )
      end
    end

    it 'counts cities and countries from geodata when columns are nil' do
      result = described_class.new(points).call

      expect(result.map(&:country)).to eq(['Germany'])
      expect(result.first.cities.map(&:city)).to eq(['Berlin'])
    end
  end
end
