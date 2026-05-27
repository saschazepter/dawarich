# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flyover countries excluded from Trip#visited_countries' do
  let(:user) { create(:user) }
  let(:trip_start) { DateTime.new(2026, 4, 5, 8, 0, 0) }
  let(:trip_end) { DateTime.new(2026, 4, 5, 23, 59, 0) }
  let(:trip) do
    create(:trip,
           user: user,
           started_at: trip_start,
           ended_at: trip_end,
           name: 'London to New York')
  end

  let!(:london_ground_stay) do
    [0, 30, 70, 90].map do |minute_offset|
      create(:point, user: user,
                     timestamp: (trip_start + minute_offset.minutes).to_i,
                     city: 'London', country_name: 'United Kingdom',
                     altitude: 30, velocity: '3',
                     lonlat: 'POINT(-0.127758 51.507351)')
    end
  end

  let!(:france_flyover) do
    fly_start = trip_start + 3.hours
    (0..30).step(5).map do |minute_offset|
      create(:point, user: user,
                     timestamp: (fly_start + minute_offset.minutes).to_i,
                     city: 'Paris', country_name: 'France',
                     altitude: 11_000, velocity: '255',
                     lonlat: 'POINT(2.349014 48.864716)')
    end
  end

  let!(:ireland_flyover) do
    fly_start = trip_start + 4.hours
    (0..30).step(5).map do |minute_offset|
      create(:point, user: user,
                     timestamp: (fly_start + minute_offset.minutes).to_i,
                     city: 'Dublin', country_name: 'Ireland',
                     altitude: 11_200, velocity: '250',
                     lonlat: 'POINT(-6.260273 53.349804)')
    end
  end

  let!(:greenland_flyover) do
    fly_start = trip_start + 7.hours
    (0..30).step(5).map do |minute_offset|
      create(:point, user: user,
                     timestamp: (fly_start + minute_offset.minutes).to_i,
                     city: 'Nuuk', country_name: 'Greenland',
                     altitude: 11_500, velocity: '260',
                     lonlat: 'POINT(-51.694138 64.181100)')
    end
  end

  let!(:nyc_ground_stay) do
    arrival = trip_start + 12.hours
    [0, 30, 70, 90].map do |minute_offset|
      create(:point, user: user,
                     timestamp: (arrival + minute_offset.minutes).to_i,
                     city: 'New York', country_name: 'United States',
                     altitude: 20, velocity: '2',
                     lonlat: 'POINT(-74.005973 40.712776)')
    end
  end

  it 'records only the ground-stay endpoints, not the flyover countries in between' do
    trip.calculate_countries
    trip.save!

    expect(trip.visited_countries.sort).to eq(['United Kingdom', 'United States'])
  end
end
