# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::OgImageJob do
  let(:link) { create(:shared_link) }

  describe '#perform' do
    it 'attaches the rendered PNG and marks state ready' do
      fake_renderer = instance_double(SharedLinks::OgImageRenderer, call: "\x89PNG\r\n\x1a\nFAKEDATA".b)
      allow(SharedLinks::OgImageRenderer).to receive(:new).and_return(fake_renderer)

      described_class.perform_now(link.id)

      reloaded = SharedLink.find(link.id)
      expect(reloaded.og_image_state).to eq('ready')
      expect(reloaded.og_image.attached?).to be true
    end

    it 'marks state failed when the renderer raises' do
      allow(SharedLinks::OgImageRenderer).to receive(:new).and_raise(StandardError, 'boom')
      described_class.perform_now(link.id)
      expect(link.reload.og_image_state).to eq('failed')
    end

    it 'returns silently when the link no longer exists' do
      expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
    end
  end
end
