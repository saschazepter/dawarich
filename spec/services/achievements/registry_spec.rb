# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::Registry do
  after { described_class.reset! }

  describe '.region_sets' do
    it 'returns the two exploration sets' do
      expect(described_class.region_sets.map(&:key)).to contain_exactly('explorer_usa', 'explorer_germany')
    end

    it 'defines 50 US states' do
      usa = described_class.find('explorer_usa')

      expect(usa.total).to eq(50)
      expect(usa.region_codes).to all(match(/\AUS-[A-Z]{2}\z/))
      expect(usa.region_codes).not_to include('US-DC')
    end

    it 'defines 16 German Bundesländer' do
      germany = described_class.find('explorer_germany')

      expect(germany.total).to eq(16)
      expect(germany.region_codes).to all(match(/\ADE-[A-Z]{2}\z/))
      expect(germany.regions['DE-BY']).to eq('Bavaria')
    end
  end
end
