# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Photoprism after filter is sent as a plain date' do
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

  it 'reduces a minute-precision start_date to the YYYY-MM-DD date Photoprism accepts' do
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

    expect(requested_after).to eq('2026-06-21')
    expect(requested_after).not_to eq(minute_precision_start_date)
  end
end
