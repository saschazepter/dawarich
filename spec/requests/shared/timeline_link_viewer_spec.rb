# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared timeline viewer', type: :request do
  let(:owner) { create(:user) }
  let(:link) do
    create(:shared_link, user: owner, resource_type: :timeline, resource_id: nil,
                         settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14',
                                     'show_places' => true, 'show_photos' => false },
                         name: 'Timeline: 2026-04-01 → 2026-04-14',
                         autobuild_trip: false)
  end

  it 'renders the date range and map container' do
    get "/s/#{link.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('April 01, 2026')
    expect(response.body).to include('April 14, 2026')
    expect(response.body).to include('shared-trip-map')
  end

  it 'embeds OG meta with timeline title' do
    get "/s/#{link.id}"
    expect(response.body).to include('property="og:title"')
    expect(response.body).to include('Timeline')
  end
end
