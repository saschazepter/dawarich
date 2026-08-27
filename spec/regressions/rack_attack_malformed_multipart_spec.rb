# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack Attack malformed multipart handling' do
  let(:app) { ->(_env) { [200, {}, ['ok']] } }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  after do
    Rack::Attack.enabled = false
  end

  def malformed_multipart_env(path, headers = {})
    Rack::MockRequest.env_for(
      path,
      method: 'POST',
      input: 'x',
      'CONTENT_LENGTH' => '1',
      'CONTENT_TYPE' => 'multipart/form-data; boundary=synthetic-boundary',
      **headers
    )
  end

  it 'uses a query-string API key when multipart parsing fails' do
    env = malformed_multipart_env('/api/v1/imports?api_key=synthetic-key')

    expect(request_api_key(Rack::Request.new(env))).to eq('synthetic-key')
    expect { Rack::Attack.new(app).call(env) }.not_to raise_error
  end

  it 'uses a bearer token when multipart parsing fails' do
    env = malformed_multipart_env(
      '/api/v1/imports',
      'HTTP_AUTHORIZATION' => 'Bearer synthetic-key'
    )

    expect(request_api_key(Rack::Request.new(env))).to eq('synthetic-key')
    expect { Rack::Attack.new(app).call(env) }.not_to raise_error
  end

  it 'preserves body-only API keys for valid requests' do
    env = Rack::MockRequest.env_for(
      '/api/v1/points',
      method: 'POST',
      input: 'api_key=body-key',
      'CONTENT_TYPE' => 'application/x-www-form-urlencoded'
    )

    expect(request_api_key(Rack::Request.new(env))).to eq('body-key')
  end

  it 'preserves parameter precedence over bearer authentication' do
    env = Rack::MockRequest.env_for(
      '/api/v1/points?api_key=query-key',
      'HTTP_AUTHORIZATION' => 'Bearer bearer-key'
    )

    expect(request_api_key(Rack::Request.new(env))).to eq('query-key')
  end
end
