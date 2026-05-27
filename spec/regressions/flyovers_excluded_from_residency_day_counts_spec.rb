# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flyover countries excluded from residency day counts' do
  let(:user) { create(:user) }
  let(:year) { 2026 }
  let(:base_ts) { DateTime.new(year, 6, 10, 8, 0, 0).to_i }

  let!(:berlin_ground_stay) do
    [0, 30, 70, 90].map do |minute_offset|
      create(:point, user: user,
                     timestamp: base_ts + minute_offset.minutes,
                     city: 'Berlin', country_name: 'Germany',
                     altitude: 50, velocity: '4',
                     lonlat: 'POINT(13.404954 52.520008)')
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

  let!(:china_flyover) do
    fly_start = base_ts + 9.hours.to_i
    (0..30).step(5).map do |minute_offset|
      create(:point, user: user,
                     timestamp: fly_start + minute_offset.minutes,
                     city: 'Beijing', country_name: 'China',
                     altitude: 11_800, velocity: '270',
                     lonlat: 'POINT(116.4074 39.9042)')
    end
  end

  let(:result) { Residency::DayCounter.new(user, year).call }

  it 'reports only the ground-stay country in the residency country list' do
    expect(result[:countries].map { |c| c[:country_name] }).to eq(['Germany'])
  end
end
