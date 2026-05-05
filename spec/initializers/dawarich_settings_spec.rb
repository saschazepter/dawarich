# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings do
  describe '.video_service_enabled?' do
    before do
      DawarichSettings.instance_variable_set(:@video_service_enabled, nil)
    end

    after do
      DawarichSettings.instance_variable_set(:@video_service_enabled, nil)
    end

    it 'returns false when VIDEO_SERVICE_URL is unset' do
      ENV.delete('VIDEO_SERVICE_URL')
      expect(described_class.video_service_enabled?).to be(false)
    end

    it 'returns true when VIDEO_SERVICE_URL is set' do
      ENV['VIDEO_SERVICE_URL'] = 'http://dawarich_video:3100'
      expect(described_class.video_service_enabled?).to be(true)
    ensure
      ENV.delete('VIDEO_SERVICE_URL')
    end
  end
end
