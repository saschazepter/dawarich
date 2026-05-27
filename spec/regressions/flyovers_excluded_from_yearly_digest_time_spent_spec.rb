# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flyover countries excluded from yearly digest time_spent_by_location' do
  let(:user) { create(:user) }
  let(:year) { 2026 }
  let(:base_ts) { DateTime.new(year, 4, 5, 8, 0, 0).to_i }

  let!(:berlin_ground_stay) do
    [0, 30, 70, 90].map do |minute_offset|
      create(:point, user: user,
                     timestamp: base_ts + minute_offset.minutes,
                     city: 'Berlin', country_name: 'Germany',
                     altitude: 50, velocity: '4',
                     lonlat: 'POINT(13.404954 52.520008)')
    end
  end

  let!(:france_flyover) do
    fly_start = base_ts + 3.hours.to_i
    (0..30).step(5).map do |minute_offset|
      create(:point, user: user,
                     timestamp: fly_start + minute_offset.minutes,
                     city: 'Paris', country_name: 'France',
                     altitude: 11_000, velocity: '255',
                     lonlat: 'POINT(2.349014 48.864716)')
    end
  end

  let!(:russia_flyover) do
    fly_start = base_ts + 5.hours.to_i
    (0..30).step(5).map do |minute_offset|
      create(:point, user: user,
                     timestamp: fly_start + minute_offset.minutes,
                     city: 'Moscow', country_name: 'Russia',
                     altitude: 11_500, velocity: '260',
                     lonlat: 'POINT(37.6173 55.7558)')
    end
  end

  let!(:athens_ground_stay) do
    arrival = base_ts + 12.hours.to_i
    [0, 30, 70, 90].map do |minute_offset|
      create(:point, user: user,
                     timestamp: arrival + minute_offset.minutes,
                     city: 'Athens', country_name: 'Greece',
                     altitude: 50, velocity: '2',
                     lonlat: 'POINT(23.727539 37.983810)')
    end
  end

  before { Stats::CalculateMonth.new(user.id, year, 4).call }

  let(:digest) { Users::Digests::CalculateYear.new(user.id, year).call }
  let(:countries_with_minutes) do
    digest.time_spent_by_location['countries'].map { |c| c['name'] }.sort
  end

  it 'reports only the ground-stay countries, omitting flyover countries from time_spent_by_location' do
    expect(countries_with_minutes).to eq(%w[Germany Greece])
  end
end
