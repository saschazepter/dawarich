# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Photoprism after filter is sent as a full ISO8601 timestamp' do
  let(:user) do
    create(
      :user,
      settings: {
        'photoprism_url' => 'http://photoprism.local',
        'photoprism_api_key' => 'test_api_key'
      }
    )
  end

  let(:minute_precision_start_date) { '2026-06-21T00:00+02:00' }
  let(:service) { Photoprism::RequestPhotos.new(user, start_date: minute_precision_start_date) }

  it 'normalizes a minute-precision start_date so the after filter carries seconds' do
    stub_request(:any, /photoprism\.local/).to_return(
      status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' }
    )

    service.call

    requested_after = nil
    expect(WebMock).to(
      have_requested(:get, /photoprism\.local/).with do |request|
        requested_after = request.uri.query_values['after']
        true
      end
    )

    expect(requested_after).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    expect(requested_after).not_to eq(minute_precision_start_date)
  end
end
