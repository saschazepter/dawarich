# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DawarichSettings do
  describe '.poster_native_render_enabled?' do
    it 'is true when POSTER_NATIVE_RENDERER is set truthy' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('POSTER_NATIVE_RENDERER', nil).and_return('true')

      expect(described_class.poster_native_render_enabled?).to be true
    end

    it 'is false when POSTER_NATIVE_RENDERER is unset' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('POSTER_NATIVE_RENDERER', nil).and_return(nil)

      expect(described_class.poster_native_render_enabled?).to be false
    end
  end

  describe '.prometheus_exporter_enabled?' do
    context 'when PROMETHEUS_EXPORTER_ENABLED is "true"' do
      it 'returns true regardless of HOST/PORT env vars' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PROMETHEUS_EXPORTER_ENABLED').and_return('true')
        expect(described_class.prometheus_exporter_enabled?).to be true
      end
    end

    context 'when PROMETHEUS_EXPORTER_ENABLED is absent' do
      it 'returns false' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PROMETHEUS_EXPORTER_ENABLED').and_return(nil)
        expect(described_class.prometheus_exporter_enabled?).to be false
      end
    end

    context 'when PROMETHEUS_EXPORTER_ENABLED is "false"' do
      it 'returns false' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PROMETHEUS_EXPORTER_ENABLED').and_return('false')
        expect(described_class.prometheus_exporter_enabled?).to be false
      end
    end
  end
end
