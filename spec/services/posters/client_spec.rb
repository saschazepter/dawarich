# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::Client do
  before do
    stub_const('POSTER_SERVICE_URL', 'http://localhost:8123')
    stub_const('POSTER_SERVICE_TOKEN', 'sekrit')
  end

  describe '#start_render' do
    it 'posts the payload to /jobs with the token header and returns the job_id' do
      stub_request(:post, 'http://localhost:8123/jobs')
        .with(headers: { 'X-Poster-Token' => 'sekrit', 'Content-Type' => 'application/json' })
        .to_return(status: 200, body: { job_id: 'abc123' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = described_class.new.start_render({ lat: 52.52, lon: 13.405 })

      expect(result).to eq('abc123')
    end

    it 'raises Error on a non-2xx response' do
      stub_request(:post, 'http://localhost:8123/jobs').to_return(status: 500)

      expect { described_class.new.start_render({}) }.to raise_error(Posters::Client::Error)
    end
  end

  describe '#job_status' do
    it 'returns the parsed status hash' do
      body = { status: 'running', phase: 'fetching_data', error: nil }.to_json
      stub_request(:get, 'http://localhost:8123/jobs/abc123')
        .with(headers: { 'X-Poster-Token' => 'sekrit' })
        .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })

      result = described_class.new.job_status('abc123')

      expect(result).to eq('status' => 'running', 'phase' => 'fetching_data', 'error' => nil)
    end

    it 'raises Error on a non-2xx response' do
      stub_request(:get, 'http://localhost:8123/jobs/missing').to_return(status: 404)

      expect { described_class.new.job_status('missing') }.to raise_error(Posters::Client::Error)
    end
  end

  describe '#job_result' do
    it 'returns the raw bytes when the job is done' do
      stub_request(:get, 'http://localhost:8123/jobs/abc123/result')
        .with(headers: { 'X-Poster-Token' => 'sekrit' })
        .to_return(status: 200, body: 'png-bytes')

      result = described_class.new.job_result('abc123')

      expect(result).to eq('png-bytes')
    end

    it 'raises Error on a 409 (not yet done)' do
      stub_request(:get, 'http://localhost:8123/jobs/abc123/result').to_return(status: 409)

      expect { described_class.new.job_result('abc123') }.to raise_error(Posters::Client::Error)
    end
  end

  describe '#themes' do
    it 'returns the parsed theme list' do
      stub_request(:get, 'http://localhost:8123/themes')
        .to_return(status: 200, body: [{ key: 'blueprint', route: '#FF6B4A' }].to_json)

      expect(described_class.new.themes).to eq([{ 'key' => 'blueprint', 'route' => '#FF6B4A' }])
    end

    it 'returns an empty list when the service is unreachable' do
      stub_request(:get, 'http://localhost:8123/themes').to_timeout

      expect(described_class.new.themes).to eq([])
    end
  end
end
