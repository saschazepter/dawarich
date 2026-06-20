# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 (maplibre)', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    Rails.cache.delete('poster_service_themes')
    if POSTER_SERVICE_URL.present?
      stub_request(:get, "#{POSTER_SERVICE_URL}/themes")
        .to_return(status: 200, body: [].to_json)
    end
  end

  describe 'poster tab gating' do
    it 'renders the poster tab button when the poster service is configured' do
      stub_const('POSTER_SERVICE_URL', 'http://localhost:8123')
      stub_const('POSTER_SERVICE_TOKEN', nil)
      Rails.cache.delete('poster_service_themes')
      stub_request(:get, 'http://localhost:8123/themes')
        .to_return(status: 200, body: [{ key: 'blueprint', name: 'Blueprint', bg: '#1A3A5C',
                                         text: '#E8F4FF', route: '#FF6B4A' }].to_json)

      get map_v2_path

      expect(response.body).to include('map-button-poster')
      expect(response.body).to include('Blueprint')
    end

    it 'omits the poster tab when the poster service is not configured' do
      stub_const('POSTER_SERVICE_URL', nil)

      get map_v2_path

      expect(response.body).not_to include('map-button-poster')
    end

    it 'does not cache an empty themes response' do
      stub_const('POSTER_SERVICE_URL', 'http://localhost:8123')
      stub_const('POSTER_SERVICE_TOKEN', nil)
      Rails.cache.delete('poster_service_themes')
      stub_request(:get, 'http://localhost:8123/themes').to_return(status: 500)

      get map_v2_path

      stub_request(:get, 'http://localhost:8123/themes')
        .to_return(status: 200, body: [{ key: 'blueprint', name: 'Blueprint', bg: '#1A3A5C',
                                         text: '#E8F4FF', route: '#FF6B4A' }].to_json)

      get map_v2_path

      expect(response.body).to include('Blueprint')
    end
  end

  describe 'GET /map/v2 date window (C1)' do
    it 'derives the data window from ?date= when start_at/end_at are absent' do
      get map_v2_path(date: '2026-05-28', panel: 'timeline')

      expect(response).to have_http_status(:ok)
      # The top date-range form must render the requested day so the map,
      # the form, and the Timeline panel all agree (no silent desync).
      expect(response.body).to include('2026-05-28T00:00')
      expect(response.body).to include('2026-05-28T23:59')
    end

    it 'still honors explicit start_at/end_at over ?date=' do
      get map_v2_path(date: '2026-05-28', start_at: '2026-05-20T00:00', end_at: '2026-05-20T23:59')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('2026-05-20T00:00')
    end

    it 'keeps the Timeline panel open across the date-range form (preserves panel param)' do
      get map_v2_path(date: 'today', panel: 'timeline')

      expect(response.body).to include('name="panel"')
      expect(response.body).to include('value="timeline"')
    end
  end
end
