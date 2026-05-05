# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Monthly stats bucketing for points near month boundary in non-UTC timezone' do
  let(:tz) { 'Europe/Berlin' }
  let(:user) { create(:user, settings: { 'timezone' => tz }) }
  let(:year) { 2026 }
  let(:month) { 3 }
  let(:timespan) do
    DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
  end
  let(:monthly_points) do
    user.points.without_raw_data.where(timestamp: timespan).order(timestamp: :asc)
  end

  let!(:home_point_march_1) do
    create(
      :point,
      user: user,
      lonlat: 'POINT(8.682 50.111)',
      timestamp: Time.utc(2026, 3, 1, 12, 0, 0).to_i
    )
  end

  let!(:flight_tail_utc_march_31) do
    create(
      :point,
      user: user,
      lonlat: 'POINT(-40.0 50.0)',
      timestamp: Time.utc(2026, 3, 31, 23, 30, 0).to_i
    )
  end

  describe Stats::DailyDistanceQuery do
    subject(:result) { described_class.new(monthly_points, timespan, tz).call }

    it 'does not attribute the cross-month flight point to day 1 of March' do
      day_1_distance = result.find { |day, _| day == 1 }&.last

      expect(day_1_distance).to eq(0)
    end

    it 'keeps the monthly total within a sane bound (no phantom transatlantic segment on day 1)' do
      total = result.sum { |_, d| d }

      expect(total).to be < 100_000
    end
  end

  describe Stats::CalculateMonth do
    it 'records a March distance close to zero (only one home point belongs to Berlin March)' do
      described_class.new(user.id, year, month).call

      stat = Stat.find_by(user: user, year: year, month: month)

      expect(stat).to be_present
      expect(stat.distance).to be < 100_000
    end
  end
end
