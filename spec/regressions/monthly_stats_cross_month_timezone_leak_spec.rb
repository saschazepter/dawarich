# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Monthly stats bucketing for points near month boundary in non-UTC timezone' do
  def create_point(user, lon, lat, time)
    create(:point, user: user, lonlat: "POINT(#{lon} #{lat})", timestamp: time.to_i)
  end

  def calculate_and_load(user, year, month)
    Stats::CalculateMonth.new(user.id, year, month).call
    Stat.find_by(user: user, year: year, month: month)
  end

  context 'Europe/Berlin (DST timezone), eastbound month boundary' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:home_point_march_1) { create_point(user, 8.682, 50.111, Time.utc(2026, 3, 1, 12, 0, 0)) }
    let!(:flight_tail_utc_march_31) { create_point(user, -40.0, 50.0, Time.utc(2026, 3, 31, 23, 30, 0)) }

    it 'does not attribute the cross-month flight point to day 1 of March' do
      stat = calculate_and_load(user, 2026, 3)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
      expect(stat.distance).to eq(0)
    end

    it 'attributes the flight point to local April day 1, not phantom March' do
      stat = calculate_and_load(user, 2026, 4)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
    end
  end

  context 'Europe/Berlin (DST timezone), westbound month boundary' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_feb_28_local_march_1_a) { create_point(user, 13.4, 52.5, Time.utc(2026, 2, 28, 23, 30, 0)) }
    let!(:point_utc_feb_28_local_march_1_b) { create_point(user, 13.5, 52.6, Time.utc(2026, 2, 28, 23, 45, 0)) }

    it 'attributes both UTC-February points to March day 1 with a measurable segment distance' do
      stat = calculate_and_load(user, 2026, 3)

      day_1 = stat.daily_distance.find { |day, _| day == 1 }&.last
      expect(day_1).to be > 0
      expect(stat.distance).to be > 0
    end

    it 'excludes the same UTC-February points from February day 28 (they belong to local March)' do
      stat = calculate_and_load(user, 2026, 2)

      expect(stat.daily_distance.find { |day, _| day == 28 }&.last).to eq(0)
    end
  end

  context 'Europe/Berlin DST spring-forward (non-boundary correctness)' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:before_dst) { create_point(user, 13.4, 52.5, Time.utc(2026, 3, 29, 0, 30, 0)) }
    let!(:after_dst) { create_point(user, 13.41, 52.51, Time.utc(2026, 3, 29, 2, 30, 0)) }

    it 'buckets both DST-spanning points into March day 29 with non-zero distance' do
      stat = calculate_and_load(user, 2026, 3)

      day_29 = stat.daily_distance.find { |day, _| day == 29 }&.last
      expect(day_29).to be > 0
      expect(stat.daily_distance.find { |day, _| day == 28 }&.last).to eq(0)
      expect(stat.daily_distance.find { |day, _| day == 30 }&.last).to eq(0)
    end
  end

  context 'Asia/Tokyo (non-DST timezone, UTC+9)' do
    let(:tz) { 'Asia/Tokyo' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_feb_28_local_march_1_a) { create_point(user, 139.69, 35.69, Time.utc(2026, 2, 28, 15, 30, 0)) }
    let!(:point_utc_feb_28_local_march_1_b) { create_point(user, 139.7, 35.7, Time.utc(2026, 2, 28, 16, 0, 0)) }
    let!(:point_utc_march_31_local_april_1) { create_point(user, 139.8, 35.8, Time.utc(2026, 3, 31, 23, 30, 0)) }

    it 'includes the UTC-Feb-28 points in Tokyo March day 1 and excludes the UTC-Mar-31 point' do
      stat = calculate_and_load(user, 2026, 3)

      day_1 = stat.daily_distance.find { |day, _| day == 1 }&.last
      expect(day_1).to be > 0
      expect(stat.distance).to be > 0
    end

    it 'does not phantom-attribute the UTC-Mar-31 point to April day 1 of Tokyo' do
      stat = calculate_and_load(user, 2026, 4)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
    end
  end

  context 'America/Los_Angeles (DST timezone, negative offset)' do
    let(:tz) { 'America/Los_Angeles' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_april_1_local_march_31_a) { create_point(user, -118.24, 34.05, Time.utc(2026, 4, 1, 5, 0, 0)) }
    let!(:point_utc_april_1_local_march_31_b) { create_point(user, -118.25, 34.06, Time.utc(2026, 4, 1, 6, 0, 0)) }

    it 'attributes both UTC-April points to local March 31 (LA PDT) with non-zero distance' do
      stat = calculate_and_load(user, 2026, 3)

      day_31 = stat.daily_distance.find { |day, _| day == 31 }&.last
      expect(day_31).to be > 0
      expect(stat.distance).to be > 0
    end

    it 'does not double-count the UTC-April points as April day 1' do
      stat = calculate_and_load(user, 2026, 4)

      expect(stat.daily_distance.find { |day, _| day == 1 }&.last).to eq(0)
    end
  end

  context 'year boundary (Europe/Berlin, Dec 31 UTC -> Jan 1 local)' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }

    let!(:point_utc_dec_31_local_jan_1_a) { create_point(user, 13.4, 52.5, Time.utc(2025, 12, 31, 23, 15, 0)) }
    let!(:point_utc_dec_31_local_jan_1_b) { create_point(user, 13.41, 52.51, Time.utc(2025, 12, 31, 23, 45, 0)) }

    it 'attributes both UTC-Dec points to local January 1 with non-zero distance, not December' do
      jan_stat = calculate_and_load(user, 2026, 1)
      dec_stat = calculate_and_load(user, 2025, 12)

      expect(jan_stat.daily_distance.find { |day, _| day == 1 }&.last).to be > 0
      expect(jan_stat.distance).to be > 0

      expect(dec_stat.daily_distance.find { |day, _| day == 31 }&.last).to eq(0)
      expect(dec_stat.distance).to eq(0)
    end
  end
end
