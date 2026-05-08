# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::BackfillTimezoneRebucketJob do
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
end
