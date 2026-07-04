# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::NativeRenderer do
  let(:poster) { create(:poster, settings: settings) }
  let(:settings) do
    {
      'lat' => 52.49, 'lon' => 13.39, 'distance' => 15_000,
      'theme' => 'autumn',
      'start_at' => '2025-10-01T00:00:00Z', 'end_at' => '2025-10-31T23:59:59Z'
    }
  end
  let(:track) do
    { 'type' => 'MultiLineString', 'coordinates' => [[[13.28, 52.44], [13.5, 52.51]]] }
  end
  let(:fake_command) { ['ruby', Rails.root.join('spec/fixtures/scripts/fake_poster_renderer.rb').to_s] }

  def build_renderer(command: fake_command)
    described_class.new(
      poster: poster,
      track: track,
      distance: 15_000,
      route_opacity: 0.6,
      subtitle: '1 Oct 2025 – 31 Oct 2025',
      command: command
    )
  end

  describe '#call' do
    it 'renders a job carrying theme tokens, track, view, and text' do
      result = build_renderer.call
      job = JSON.parse(result[:png])

      expect(job['tokens']['name']).to eq('Autumn')
      expect(job['trackGeojson']['geometry']['type']).to eq('MultiLineString')
      expect(job['view']).to include('lat' => 52.49, 'lon' => 13.39, 'distance' => 15_000)
      expect(job['trackOpacity']).to eq(0.6)
      expect(job['text']).to include('title' => 'Berlin', 'subtitle' => '1 Oct 2025 – 31 Oct 2025')
      expect(job['output']).to include('widthMm' => 300, 'heightMm' => 400)
      expect(result[:pdf]).to eq('PDF:Berlin')
    end

    it 'renders the explicit settings title when present' do
      poster.settings['title'] = 'My Trip'

      job = JSON.parse(build_renderer.call[:png])

      expect(job['text']['title']).to eq('My Trip')
    end

    it 'renders a blank title when the settings title is blank (untitled poster)' do
      poster.update!(name: 'Untitled poster', settings: poster.settings.merge('title' => ''))

      job = JSON.parse(build_renderer.call[:png])

      expect(job['text']['title']).to eq('')
    end

    it 'raises when the renderer process fails' do
      renderer = build_renderer(command: ['ruby', '-e', 'warn "boom"; exit 1'])

      expect { renderer.call }.to raise_error(described_class::Error, /boom/)
    end

    it 'raises when the theme tokens are unknown' do
      poster.settings['theme'] = 'nonexistent_theme'

      expect { build_renderer.call }.to raise_error(described_class::Error, /theme/i)
    end
  end
end
