# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BackfillScheduler do
  let(:user) { create(:user) }
  let(:window_start) { Tracks::IncrementalGenerator::LOOKBACK_HOURS.hours.ago.to_i }

  after do
    described_class.clear(user.id)
  end

  describe '#call' do
    it 'does nothing for an empty batch' do
      expect { described_class.new(user.id, []).call }
        .not_to have_enqueued_job(Tracks::BackfillGenerationJob)
    end

    it 'does nothing when every timestamp is inside the lookback window' do
      expect { described_class.new(user.id, [window_start + 60, window_start + 120]).call }
        .not_to have_enqueued_job(Tracks::BackfillGenerationJob)
    end

    it 'schedules a backfill job when the earliest timestamp predates the window' do
      expect { described_class.new(user.id, [window_start - 1, window_start + 60]).call }
        .to have_enqueued_job(Tracks::BackfillGenerationJob).with(user.id)
    end
  end

  describe 'range accumulation across a burst' do
    let(:day) { Time.zone.local(2024, 6, 15, 12, 0, 0).to_i }

    it 'peeks the widest min/max seen across all triggers' do
      described_class.new(user.id, [day, day + 100]).call
      described_class.new(user.id, [day - 86_400, day + 100]).call

      expect(described_class.peek_range(user.id)).to eq([day - 86_400, day + 100])
    end

    it 'leaves the range intact for a retry until it is cleared' do
      described_class.new(user.id, [day]).call

      expect(described_class.peek_range(user.id)).to eq([day, day])
      expect(described_class.peek_range(user.id)).to eq([day, day])

      described_class.clear(user.id)

      expect(described_class.peek_range(user.id)).to be_nil
    end
  end
end
