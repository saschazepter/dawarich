# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::BackfillTimezoneRebucketJob do
  include ActiveJob::TestHelper

  describe '#perform' do
    let(:user) { create(:user) }

    before do
      create(:stat, user: user, year: 2026, month: 1)
      create(:stat, user: user, year: 2026, month: 2)
      create(:stat, user: user, year: 2026, month: 3)
    end

    it 'enqueues Stats::CalculatingJob for every existing stat row' do
      expect { described_class.new.perform }
        .to have_enqueued_job(Stats::CalculatingJob).exactly(3).times
    end

    it 'enqueues with the correct (user_id, year, month) tuple per stat' do
      described_class.new.perform

      expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2026, 1)
      expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2026, 2)
      expect(Stats::CalculatingJob).to have_been_enqueued.with(user.id, 2026, 3)
    end
  end

  describe 'inline recompute' do
    let(:tz) { 'Europe/Berlin' }
    let(:user) { create(:user, settings: { 'timezone' => tz }) }
    let!(:stale_stat) do
      Stat.create!(user: user, year: 2026, month: 3,
                   daily_distance: { '1' => 9000 }, distance: 9000)
    end

    before do
      create(:point, user: user, lonlat: 'POINT(13.4 52.5)',
                     timestamp: Time.utc(2026, 3, 15, 9, 0, 0).to_i)
      create(:point, user: user, lonlat: 'POINT(13.5 52.6)',
                     timestamp: Time.utc(2026, 3, 15, 9, 30, 0).to_i)
    end

    it 'replaces the stored UTC-bucketed daily_distance with the local-tz bucketing' do
      perform_enqueued_jobs do
        described_class.new.perform
      end

      stale_stat.reload
      expect(stale_stat.daily_distance.find { |day, _| day == 15 }&.last.to_i).to be > 0
      expect(stale_stat.distance).to be > 0
    end
  end
end
