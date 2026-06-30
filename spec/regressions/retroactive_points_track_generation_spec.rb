# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Retroactive point ingestion schedules historical track generation' do
  let(:user) { create(:user) }

  def params_for(timestamps)
    {
      locations: timestamps.each_with_index.map do |ts, index|
        {
          type: 'Feature',
          geometry: { type: 'Point', coordinates: [13.40 + (index * 0.001), 52.50 + (index * 0.001)] },
          properties: { timestamp: ts.iso8601 }
        }
      end
    }
  end

  context 'when the batch is older than the realtime lookback window' do
    let(:anchor) { Time.zone.local(2024, 6, 15, 10, 0, 0) }
    let(:timestamps) { [anchor, anchor + 5.minutes, anchor + 10.minutes] }

    it 'enqueues a scoped bulk track generation for the affected window' do
      expect { Points::Create.new(user, params_for(timestamps)).call }
        .to have_enqueued_job(Tracks::ParallelGeneratorJob)
        .with(
          user.id,
          hash_including(
            start_at: timestamps.first.beginning_of_day,
            end_at: timestamps.last.end_of_day,
            mode: :bulk
          )
        )
    end
  end

  context 'when the batch falls within the realtime lookback window' do
    let(:timestamps) { [30.minutes.ago, 25.minutes.ago, 20.minutes.ago] }

    it 'does not enqueue a bulk track generation' do
      expect { Points::Create.new(user, params_for(timestamps)).call }
        .not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
    end
  end
end
