# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Memories::Builder do
  let(:user) { create(:user) }
  let(:anchor) { Time.zone.local(2026, 5, 21, 12) }

  def plant_point(at:, city:, country:, lat:, lon:)
    create(:point, user: user,
                   timestamp: at.to_i,
                   latitude: lat, longitude: lon,
                   lonlat: "POINT(#{lon} #{lat})",
                   city: city, country: country)
  end

  subject(:memories) { described_class.new(user, anchor: anchor).call }

  context 'when the user has no points anywhere' do
    it 'returns an empty list (no memories to surface yet)' do
      expect(memories).to be_empty
    end
  end

  context 'with points planted at exactly 1 month, 1 year, and 5 years ago' do
    before do
      plant_point(at: anchor - 1.month,  city: 'Berlin', country: 'Germany',
                  lat: 52.52, lon: 13.40)
      plant_point(at: anchor - 1.year,   city: 'Rome',   country: 'Italy',
                  lat: 41.90, lon: 12.50)
      plant_point(at: anchor - 5.years,  city: 'Tokyo',  country: 'Japan',
                  lat: 35.68, lon: 139.69)
    end

    it 'surfaces exactly one memory per non-empty lookback slot' do
      expect(memories.length).to eq(3)
    end

    it 'orders memories from most recent to most distant' do
      expect(memories.map { _1[:period_key] }).to eq(%w[months_ago_1 years_ago_1 years_ago_5])
    end

    it 'attaches a human-readable period_label and short chip text' do
      expect(memories.map { _1[:period_label] })
        .to eq(['1 month ago', '1 year ago', '5 years ago'])
      expect(memories.map { _1[:period_short] }).to eq(%w[1mo 1y 5y])
    end

    it 'names each memory after the dominant city that day' do
      expect(memories.map { _1[:name] }).to eq(%w[Berlin Rome Tokyo])
    end

    it 'embeds lat/lon as floats so the JSON payload serializes cleanly' do
      expect(memories.first[:lat]).to be_a(Float).and(be_within(0.01).of(52.52))
      expect(memories.first[:lon]).to be_a(Float).and(be_within(0.01).of(13.40))
    end

    it 'resolves the iso_a2 country code for each memory' do
      memories.each { |m| expect(m[:country]).to match(/\A[A-Z]{2}\z/) }
    end

    it 'tags each memory with a time bucket so the UI can dim distant entries' do
      bucket_for = memories.to_h { |m| [m[:period_key], m[:bucket]] }
      expect(bucket_for['months_ago_1']).to eq(:recent)
      expect(bucket_for['years_ago_1']).to eq(:mid)
      expect(bucket_for['years_ago_5']).to eq(:distant)
    end

    it 'attaches a non-empty caption_html mentioning the city' do
      memories.each do |m|
        expect(m[:caption_html]).to be_present
        expect(m[:caption_html]).to include(m[:name])
      end
    end
  end

  context 'when a lookback slot has multiple cities on the same day' do
    before do
      plant_point(at: anchor - 1.month, city: 'Berlin',  country: 'Germany',
                  lat: 52.52, lon: 13.40)
      plant_point(at: anchor - 1.month + 1.hour, city: 'Berlin', country: 'Germany',
                  lat: 52.52, lon: 13.40)
      plant_point(at: anchor - 1.month + 2.hours, city: 'Potsdam', country: 'Germany',
                  lat: 52.39, lon: 13.06)
    end

    it 'picks the dominant city (most points) for the memory name' do
      expect(memories.first[:name]).to eq('Berlin')
    end

    it 'reports the full list of cities visited that day' do
      expect(memories.first[:cities]).to contain_exactly('Berlin', 'Potsdam')
    end
  end

  context 'when a point falls on the day but has no city (uncategorized)' do
    before do
      plant_point(at: anchor - 1.year, city: nil, country: nil, lat: 0.0, lon: 0.0)
    end

    it 'skips the memory rather than surfacing a nameless slot' do
      expect(memories).to be_empty
    end
  end

  context 'when the exact N-ago day is empty but a nearby day within ±3 days has points' do
    before do
      plant_point(at: anchor - 1.year + 2.days, city: 'Lisbon', country: 'Portugal',
                  lat: 38.72, lon: -9.14)
    end

    it 'surfaces the nearest non-empty day as the memory' do
      chapter = memories.find { _1[:period_key] == 'years_ago_1' }
      expect(chapter[:name]).to eq('Lisbon')
    end

    it 'records the offset_days so the UI can hint at the date shift' do
      chapter = memories.find { _1[:period_key] == 'years_ago_1' }
      expect(chapter[:offset_days]).to eq(2)
    end

    it 'mentions the shift in caption_html (e.g. "2 days after")' do
      chapter = memories.find { _1[:period_key] == 'years_ago_1' }
      expect(chapter[:caption_html]).to include('2 days after')
    end
  end

  context 'when both a point on the target day and a busier day within ±3 days exist' do
    before do
      plant_point(at: anchor - 1.year, city: 'Sofia', country: 'Bulgaria',
                  lat: 42.7, lon: 23.3)
      3.times do |i|
        plant_point(at: anchor - 1.year + 1.day + i.hours,
                    city: 'Athens', country: 'Greece', lat: 37.98, lon: 23.72)
      end
    end

    it 'prefers the busier day even if the exact day has data' do
      chapter = memories.find { _1[:period_key] == 'years_ago_1' }
      expect(chapter[:name]).to eq('Athens')
      expect(chapter[:offset_days]).to eq(1)
    end
  end

  context 'when window_days: 0 is passed explicitly (strict same-day mode)' do
    let(:memories) { described_class.new(user, anchor: anchor, window_days: 0).call }

    before do
      plant_point(at: anchor - 1.year + 2.days, city: 'Lisbon', country: 'Portugal',
                  lat: 38.72, lon: -9.14)
    end

    it 'does NOT surface the nearby day — strict same-day only' do
      expect(memories.map { _1[:period_key] }).not_to include('years_ago_1')
    end
  end
end
