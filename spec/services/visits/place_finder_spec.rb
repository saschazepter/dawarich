# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::PlaceFinder do
  let(:user) { create(:user) }
  let(:visit_data) do
    {
      center_lat: 52.5126,
      center_lon: 13.4012,
      suggested_name: nil,
      points: [],
      start_time: Time.zone.now.to_i,
      end_time: (Time.zone.now + 1.hour).to_i,
      duration: 3600
    }
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
  end

  describe '#find_or_create_place' do
    it 'returns a Place (not a hash)' do
      allow(Places::NameFetcher).to receive(:lookup_attrs).and_return(
        { name: 'Café Bravo', city: 'Berlin', country: 'Germany', geodata: { 'properties' => {} } }
      )

      result = described_class.new(user).find_or_create_place(visit_data)

      expect(result).to be_a(Place)
      expect(result.name).to eq('Café Bravo')
    end

    it 'creates exactly ONE place per call (no fan-out)' do
      allow(Places::NameFetcher).to receive(:lookup_attrs).and_return(
        { name: 'Café Bravo', city: 'Berlin', country: 'Germany', geodata: {} }
      )

      expect { described_class.new(user).find_or_create_place(visit_data) }
        .to change { Place.count }.by(1)
    end

    it 'falls back to Place::DEFAULT_NAME when Photon returns nothing' do
      allow(Places::NameFetcher).to receive(:lookup_attrs).and_return(nil)

      result = described_class.new(user).find_or_create_place(visit_data)

      expect(result.name).to eq(Place::DEFAULT_NAME)
      expect(result.source).to eq('photon')
    end

    it 'uses suggested_name when Photon returns nothing and suggested_name is present' do
      allow(Places::NameFetcher).to receive(:lookup_attrs).and_return(nil)
      data = visit_data.merge(suggested_name: 'Home')

      expect(described_class.new(user).find_or_create_place(data).name).to eq('Home')
    end

    it 'reuses an existing user place near the center' do
      existing = create(:place, user: user, latitude: 52.5126, longitude: 13.4012)
      expect(Places::NameFetcher).not_to receive(:lookup_attrs)

      expect(described_class.new(user).find_or_create_place(visit_data)).to eq(existing)
    end

    it 'does NOT persist geodata when store_geodata? is false' do
      allow(Places::NameFetcher).to receive(:lookup_attrs).and_return(
        { name: 'Café Bravo', city: 'Berlin', country: 'Germany',
          geodata: { 'properties' => { 'osm_id' => 1 } } }
      )

      result = described_class.new(user).find_or_create_place(visit_data)
      expect(result.geodata).to eq({})
    end
  end
end
