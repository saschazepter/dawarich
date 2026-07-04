# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 (maplibre)', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'poster tab gating' do
    it 'renders the poster tab button when the posters flag is enabled' do
      Flipper.enable(:posters)

      get map_v2_path

      expect(response.body).to include('map-button-poster')
    end

    it 'omits the poster tab when the posters flag is disabled' do
      Flipper.disable(:posters)

      get map_v2_path

      expect(response.body).not_to include('map-button-poster')
    end

    it 'renders the vendored poster theme tokens for the map colour editor' do
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

  describe 'share hub entry' do
    it 'renders a Share button opening the share hub in the share-link-modal frame' do
      get map_v2_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(share_links_hub_path)
      expect(response.body).to include('timeline-share-button')
      expect(response.body).to include('share-link-modal')
    end
  end
end
