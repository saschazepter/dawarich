# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Videos::RequestRender do
  let(:user) { create(:user) }
  let(:track) { create(:track, user:, start_at: 1.day.ago, end_at: 1.day.ago + 30.minutes) }
  let(:video) { create(:video, user:, track:) }
  let(:service_url) { 'http://dawarich_video:3100/api/render' }

  before do
    ENV['VIDEO_SERVICE_URL'] = 'http://dawarich_video:3100'
    ENV['APPLICATION_HOSTS'] = 'dawarich_app,localhost'
    ENV['APPLICATION_PROTOCOL'] = 'http'
  end

  after do
    ENV.delete('VIDEO_SERVICE_URL')
    ENV.delete('APPLICATION_HOSTS')
    ENV.delete('APPLICATION_PROTOCOL')
    ENV.delete('VIDEO_SERVICE_AUTH_TOKEN')
  end

  describe '#call' do
    context 'with track points' do
      before do
        create(:point, user:, track:, longitude: 13.4, latitude: 52.5,
                       timestamp: track.start_at.to_i)
        create(:point, user:, track:, longitude: 13.5, latitude: 52.6,
                       timestamp: track.start_at.to_i + 60)
      end

      it 'POSTs JSON with coordinates and callback URLs and returns the response' do
        stub = stub_request(:post, service_url)
               .with do |req|
                 body = JSON.parse(req.body)
                 expect(body['video_id']).to eq(video.id)
                 expect(body['coordinates'].length).to eq(2)
                 expect(body['callback_urls']).to include(
                   match(%r{http://dawarich_app/api/v1/videos/#{video.id}/callback}),
                   match(%r{http://localhost/api/v1/videos/#{video.id}/callback})
                 )
                 expect(body['callback_url']).to eq(body['callback_urls'].first)
                 expect(body['config']).to eq({ 'map_behavior' => 'fit_full_route' })
                 true
               end
               .to_return(status: 200, body: '{}')

        described_class.new(video:).call
        expect(stub).to have_been_requested
      end

      it 'sends Authorization header when VIDEO_SERVICE_AUTH_TOKEN is set' do
        ENV['VIDEO_SERVICE_AUTH_TOKEN'] = 'sekrit'
        stub = stub_request(:post, service_url)
               .with(headers: { 'Authorization' => 'Bearer sekrit' })
               .to_return(status: 200, body: '{}')
        described_class.new(video:).call
        expect(stub).to have_been_requested
      end
    end

    context 'when no points fall in the date range' do
      let(:video) { create(:video, user:, track: nil) }

      it 'raises RenderError' do
        expect { described_class.new(video:).call }
          .to raise_error(Videos::RequestRender::RenderError, /No coordinates/)
      end
    end

    context 'when video service returns non-2xx' do
      let(:video) do
        v = create(:video, user:, track:)
        create(:point, user:, track:, longitude: 13.4, latitude: 52.5,
                       timestamp: track.start_at.to_i)
        v
      end

      it 'raises RenderError with the response code' do
        stub_request(:post, service_url).to_return(status: 500, body: '{"error":"boom"}')
        expect { described_class.new(video:).call }
          .to raise_error(Videos::RequestRender::RenderError, /500/)
      end
    end

    context 'when the coordinate set exceeds 50_000' do
      it 'downsamples to 50_000 preserving first and last' do
        coords = Array.new(60_000) { |i| [13.4 + (i * 0.0001), 52.5, i] }
        service = described_class.new(video:)
        result = service.send(:downsample, coords)
        expect(result.length).to eq(50_000)
        expect(result.first).to eq(coords.first)
        expect(result.last).to eq(coords.last)
      end
    end
  end
end
