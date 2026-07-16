# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'malformed persisted toponyms' do
  let(:user) { create(:user) }
  let(:malformed_toponyms) do
    [
      'not_a_hash',
      { 'country' => 'Spain', 'cities' => 'not_an_array' },
      { 'country' => 'Italy', 'cities' => [{ 'city' => nil }, { 'not_city' => 'Rome' }] },
      [{ 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }]
    ]
  end

  def create_stat_with_toponyms(owner, toponyms, year: 2026, month: 1)
    create(:stat, user: owner, year:, month:).tap do |stat|
      stat.update_column(:toponyms, toponyms)
      stat.reload
    end
  end

  describe Stat, type: :model do
    it 'drops malformed entries and normalizes cities' do
      stat = create_stat_with_toponyms(user, malformed_toponyms)

      expect(stat.toponyms).to eq(
        [
          { 'country' => 'Spain', 'cities' => [] },
          { 'country' => 'Italy', 'cities' => [] },
          { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
        ]
      )
    end

    it 'returns an empty array when the column holds a non-array value' do
      stat = create_stat_with_toponyms(user, 'not_an_array')

      expect(stat.toponyms).to eq([])
    end

    it 'normalizes calculator structs on assignment so unreloaded reads keep the data' do
      stat = create(:stat, user:, year: 2026, month: 3)
      stat.toponyms = [
        CountriesAndCities::CountryData.new(
          country: 'Germany',
          cities: [CountriesAndCities::CityData.new(city: 'Berlin', points: 5, timestamp: 123, stayed_for: 60)]
        )
      ]

      expect(stat.toponyms).to eq(
        [
          {
            'country' => 'Germany',
            'cities' => [{ 'city' => 'Berlin', 'points' => 5, 'timestamp' => 123, 'stayed_for' => 60 }]
          }
        ]
      )
    end

    it 'logs a warning when malformed entries are sanitized' do
      stat = create_stat_with_toponyms(user, malformed_toponyms)
      allow(Rails.logger).to receive(:warn)

      stat.toponyms

      expect(Rails.logger).to have_received(:warn).with(/malformed toponym/)
    end

    it 'reports sanitized malformed data to the exception tracker' do
      stat = create_stat_with_toponyms(user, malformed_toponyms)
      allow(ExceptionReporter).to receive(:call)

      stat.toponyms

      expect(ExceptionReporter).to have_received(:call).with('Malformed Stat toponyms sanitized', /Stat##{stat.id}/)
    end

    it 'sanitizes and logs only once across repeated reads' do
      stat = create_stat_with_toponyms(user, malformed_toponyms)
      allow(Rails.logger).to receive(:warn)

      3.times { stat.toponyms }

      expect(Rails.logger).to have_received(:warn).once
    end

    it 'drops the memoized value on assignment and reload' do
      stat = create_stat_with_toponyms(user, malformed_toponyms)
      stat.toponyms

      stat.toponyms = [{ 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }]
      expect(stat.toponyms).to eq([{ 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }])

      stat.reload
      expect(stat.toponyms).to eq(
        [
          { 'country' => 'Spain', 'cities' => [] },
          { 'country' => 'Italy', 'cities' => [] },
          { 'country' => 'France', 'cities' => [{ 'city' => 'Paris' }] }
        ]
      )
    end

    it 'does not log for well-formed toponyms' do
      stat = create(:stat, user:, year: 2026, month: 4)
      allow(Rails.logger).to receive(:warn)

      stat.toponyms

      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  describe StatsHelper, type: :helper do
    it 'skips malformed values in annual statistics' do
      stats = [
        create_stat_with_toponyms(user, malformed_toponyms, month: 1),
        create_stat_with_toponyms(user, 'not_an_array', month: 2)
      ]

      result = helper.countries_and_cities_stat_for_year(2026, stats)

      expect(result).to include(
        countries_count: 1,
        cities_count: 1,
        grouped_by_country: { 'France' => ['Paris'] }
      )
    end

    it 'skips malformed values in monthly statistics' do
      stat = create_stat_with_toponyms(user, malformed_toponyms)

      expect(helper.countries_and_cities_stat_for_month(stat)).to eq('1 countries, 1 cities')
      expect(helper.countries_visited(stat)).to eq(1)
    end
  end

  describe 'stats month page', type: :request do
    before { sign_in user }

    it 'renders when current and previous months hold malformed toponyms' do
      create_stat_with_toponyms(user, 'not_an_array', year: 2026, month: 1)
      create_stat_with_toponyms(user, malformed_toponyms, year: 2026, month: 2)

      get '/stats/2026/2'

      expect(response.status).to eq(200)
      expect(response.body).to include('France')
    end
  end

  describe 'public month page', type: :request do
    it 'renders a shared stat with malformed toponyms' do
      stat = create_stat_with_toponyms(user, malformed_toponyms)
      stat.enable_sharing!(expiration: '24h')

      get "/shared/month/#{stat.sharing_uuid}"

      expect(response.status).to eq(200)
    end
  end
end
