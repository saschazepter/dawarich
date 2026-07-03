# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::Generate do
  let(:poster) { create(:poster) }
  let(:track) { { 'type' => 'MultiLineString', 'coordinates' => [[[13.40, 52.51], [13.41, 52.52]]] } }

  before do
    stub_const('POSTER_SERVICE_URL', 'http://localhost:8123')
    stub_const('POSTER_SERVICE_TOKEN', nil)
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  def run_generate
    described_class.new(poster).call
  end

  def stub_successful_render(track_body: 'png-bytes')
    stub_request(:post, 'http://localhost:8123/jobs')
      .to_return(status: 200, body: { job_id: 'job-1' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, 'http://localhost:8123/jobs/job-1')
      .to_return(
        { status: 200, body: { status: 'running', phase: 'fetching_data', error: nil }.to_json,
          headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: { status: 'done', phase: 'saving', error: nil }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      )
    stub_request(:get, 'http://localhost:8123/jobs/job-1/result')
      .to_return(status: 200, body: track_body)
  end

  context 'when the render succeeds' do
    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      stub_successful_render
    end

    it 'attaches the image and completes the poster' do
      run_generate

      expect(poster.reload).to be_completed
      expect(poster.image).to be_attached
      expect(poster.image.download).to eq('png-bytes')
    end

    it 'attaches a print-ready PDF' do
      run_generate

      expect(poster.reload.print_pdf).to be_attached
      expect(poster.print_pdf.content_type).to eq('application/pdf')
      expect(poster.print_pdf.filename.to_s).to end_with('.pdf')
    end

    it 'requests a PDF render from the service' do
      run_generate

      request_matcher = have_requested(:post, 'http://localhost:8123/jobs').with do |req|
        JSON.parse(req.body)['format'] == 'pdf'
      end
      expect(WebMock).to request_matcher
    end

    it 'defaults route style to translucent density at 60%' do
      run_generate

      request_matcher = have_requested(:post, 'http://localhost:8123/jobs').with do |req|
        body = JSON.parse(req.body)
        body['format'] == 'png' && body['route_fill'] == false && (body['route_opacity'] - 0.6).abs < 1e-6
      end
      expect(WebMock).to request_matcher
    end
  end

  context 'when settings request a solid fill and a percentage opacity' do
    let(:poster) do
      create(:poster, settings: attributes_for(:poster)[:settings].merge('route_fill' => '1', 'route_opacity' => '40'))
    end

    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      stub_successful_render
    end

    it 'forwards solid fill and the opacity as a 0-1 decimal' do
      run_generate

      request_matcher = have_requested(:post, 'http://localhost:8123/jobs').with do |req|
        body = JSON.parse(req.body)
        body['format'] == 'png' && body['route_fill'] == true && (body['route_opacity'] - 0.4).abs < 1e-6
      end
      expect(WebMock).to request_matcher
    end

    it 'sends title, subtitle, theme and route to the service' do
      run_generate

      request_matcher = have_requested(:post, 'http://localhost:8123/jobs').with do |req|
        body = JSON.parse(req.body)
        body['format'] == 'png' &&
          body['title'] == 'Berlin' &&
          body['theme'] == 'terracotta' &&
          body['subtitle'] == '1 Apr 2026 – 30 Apr 2026' &&
          body['route_geojson'] == track
      end
      expect(WebMock).to request_matcher
    end

    it 'records render phases on the poster' do
      run_generate

      expect(poster.reload.settings['progress_phase']).to eq('fetching_data')
    end
  end

  context 'when the job reports failure' do
    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      stub_request(:post, 'http://localhost:8123/jobs')
        .to_return(status: 200, body: { job_id: 'job-1' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'http://localhost:8123/jobs/job-1')
        .to_return(status: 200, body: { status: 'failed', phase: nil, error: 'boom' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'fails the poster with the error message' do
      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/unavailable/i)
    end
  end

  context 'when there are no points in range' do
    before { allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(nil) }

    it 'fails with a user-facing error and makes no HTTP call' do
      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/No location data/)
      expect(WebMock).not_to have_requested(:post, 'http://localhost:8123/jobs')
    end
  end

  context 'when the service errors' do
    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      stub_request(:post, 'http://localhost:8123/jobs').to_return(status: 500)
    end

    it 'fails with a service-unavailable error' do
      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/unavailable/i)
    end
  end

  context 'when a network error escapes the client' do
    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      stub_request(:post, 'http://localhost:8123/jobs').to_raise(SocketError)
    end

    it 'fails with a service-unavailable error' do
      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/unavailable/i)
    end
  end

  context 'when the track is outside the cropped poster area but within the raw distance' do
    let(:nearby_track) { { 'type' => 'MultiLineString', 'coordinates' => [[[13.405, 52.55], [13.406, 52.551]]] } }

    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(nearby_track)
      stub_successful_render
    end

    it 'fails with an area mismatch error' do
      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/does not pass through/)
    end
  end

  context 'when the track does not pass through the poster area' do
    let(:distant_track) { { 'type' => 'MultiLineString', 'coordinates' => [[[14.42, 50.08], [14.43, 50.09]]] } }

    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(distant_track)
      stub_successful_render
    end

    it 'fails with an area mismatch error and makes no HTTP call' do
      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to match(/does not pass through/)
      expect(WebMock).not_to have_requested(:post, 'http://localhost:8123/jobs')
    end
  end

  context 'when the requested distance exceeds the service limit' do
    let(:poster) { create(:poster, settings: attributes_for(:poster)[:settings].merge('distance' => 150_000)) }

    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      stub_successful_render
    end

    it 'clamps the distance to 20km' do
      run_generate

      request_matcher = have_requested(:post, 'http://localhost:8123/jobs').with do |req|
        body = JSON.parse(req.body)
        body['format'] == 'png' && body['distance'] == 20_000
      end
      expect(WebMock).to request_matcher
    end
  end

  context 'when the poster is already completed' do
    let(:poster) { create(:poster, status: :completed) }

    before do
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      stub_successful_render
    end

    it 'makes no HTTP call and stays completed' do
      run_generate

      expect(poster.reload).to be_completed
      expect(WebMock).not_to have_requested(:post, 'http://localhost:8123/jobs')
    end
  end

  context "when settings include source: 'tracks'" do
    let(:poster) { create(:poster, settings: attributes_for(:poster)[:settings].merge('source' => 'tracks')) }

    before do
      allow_any_instance_of(Posters::TracksBuilder).to receive(:call).and_return(track)
      stub_successful_render
    end

    it 'builds the route from tracks and completes the poster' do
      run_generate

      expect(poster.reload).to be_completed
      request_matcher = have_requested(:post, 'http://localhost:8123/jobs').with do |req|
        body = JSON.parse(req.body)
        body['format'] == 'png' && body['route_geojson'] == track
      end
      expect(WebMock).to request_matcher
    end
  end
  context 'when the native renderer is enabled' do
    before do
      allow(DawarichSettings).to receive(:poster_native_render_enabled?).and_return(true)
      allow_any_instance_of(Posters::TrackBuilder).to receive(:call).and_return(track)
      allow(Posters::NativeRenderer).to receive(:new).and_return(
        instance_double(Posters::NativeRenderer, call: { png: 'native-png', pdf: 'native-pdf' })
      )
    end

    it 'attaches both outputs from the native renderer and completes' do
      run_generate

      expect(poster.reload).to be_completed
      expect(poster.image.download).to eq('native-png')
      expect(poster.print_pdf.download).to eq('native-pdf')
    end

    it 'never talks to the sidecar' do
      run_generate

      expect(WebMock).not_to have_requested(:post, 'http://localhost:8123/jobs')
    end

    it 'fails the poster when the native renderer errors' do
      allow(Posters::NativeRenderer).to receive(:new).and_raise(Posters::NativeRenderer::Error, 'render exploded')

      run_generate

      expect(poster.reload).to be_failed
      expect(poster.settings['error']).to be_present
    end
  end
end
