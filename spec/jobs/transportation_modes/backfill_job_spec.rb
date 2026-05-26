# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::BackfillJob do
  describe '#perform' do
    let(:user) do
      create(:user, settings: {
               'enabled_transportation_modes' => %w[stationary walking driving],
               'time_threshold_minutes' => '30'
             })
    end

    let!(:track) do
      create(:track, user: user,
                     start_at: 1.hour.ago,
                     end_at: 30.minutes.ago,
                     distance: 0,
                     dominant_mode: :unknown)
    end

    let!(:points) do
      base = 1.hour.ago.to_i
      18.times.map do |i|
        create(:point, user: user, track: track,
                       lonlat: "POINT(#{-74.0060 + (i * 0.0010)} #{40.7128 + (i * 0.0005)})",
                       timestamp: base + (i * 30),
                       altitude: 100,
                       velocity: 4.5)
      end
    end

    it 'does not assign cycling segments when cycling is disabled in user settings' do
      described_class.new.perform(user.id)

      modes = track.reload.track_segments.pluck(:transportation_mode)
      expect(modes).not_to include('cycling')
    end
  end
end
