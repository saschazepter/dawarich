# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared::Links', type: :request do
  describe 'GET /s/:id' do
    it 'returns 404 when the link does not exist' do
      get '/s/00000000-0000-0000-0000-000000000000'
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the link is revoked' do
      link = create(:shared_link, :revoked)
      get "/s/#{link.id}"
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the link is expired' do
      link = create(:shared_link, :expired)
      get "/s/#{link.id}"
      expect(response).to have_http_status(:not_found)
    end

    it 'sets X-Robots-Tag header on the 404 response' do
      get '/s/00000000-0000-0000-0000-000000000000'
      expect(response.headers['X-Robots-Tag']).to include('noindex')
    end
  end

  describe 'happy-path GET /s/:id for a trip' do
    let(:owner) { create(:user) }
    let(:trip) do
      create(:trip, user: owner, name: 'Norway 2026',
                    started_at: Time.utc(2026, 4, 1), ended_at: Time.utc(2026, 4, 14))
    end
    let(:link) { create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id, name: 'Norway 2026') }

    it 'renders the trip viewer with the trip name' do
      get "/s/#{link.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Norway 2026')
    end

    it 'increments view_count' do
      expect { get "/s/#{link.id}" }.to change { link.reload.view_count }.by(1)
    end

    it 'embeds OG meta tags' do
      get "/s/#{link.id}"
      expect(response.body).to include('property="og:title"')
      expect(response.body).to include('Norway 2026')
    end

    it 'sets X-Robots-Tag noindex on the active response' do
      get "/s/#{link.id}"
      expect(response.headers['X-Robots-Tag']).to include('noindex')
    end
  end

  describe 'happy-path GET /s/:id for a track' do
    let(:owner) { create(:user) }
    let(:track) do
      create(:track, user: owner, dominant_mode: :driving, distance: 42_000,
                     start_at: Time.utc(2026, 5, 12), end_at: Time.utc(2026, 5, 12, 1))
    end
    let(:link) do
      create(:shared_link, user: owner, resource_type: :track, resource_id: track.id,
                           settings: { 'show_stats' => true })
    end

    it 'renders the track viewer with the map container and derived label' do
      get "/s/#{link.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('shared-trip-map')
      expect(response.body).to include('Driving')
    end

    it 'shows a stats block with distance when show_stats is on' do
      get "/s/#{link.id}"
      expect(response.body).to include('Distance')
    end

    it 'shows the phrase prompt first for a phrase-protected track share' do
      link.update!(magic_phrase: 'blau-tiger-berg')
      get "/s/#{link.id}"
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('magic phrase')
    end
  end

  describe 'happy-path GET /s/:id for a live share' do
    let(:owner) { create(:user) }
    let(:link) { create(:shared_link, :live, user: owner, name: 'Live location') }

    it 'renders the live map container wired to its own consumer (link id, no unlock token)' do
      get "/s/#{link.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('shared-live-map')
      expect(response.body).to include(link.id)
      expect(response.body).not_to include(link.unlock_token.to_s) if link.unlock_token
    end
  end

  describe 'dispatch for a resource_type without a partial' do
    let(:link) { create(:shared_link, resource_type: :trip) }

    it 'renders the unsupported view with 200 instead of raising MissingTemplate' do
      allow_any_instance_of(SharedLink).to receive(:resource_type).and_return('mystery')
      get "/s/#{link.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('share type is no longer supported')
    end
  end

  describe 'phrase-protected links' do
    let(:link) { create(:shared_link, :with_phrase) }

    it 'shows the phrase prompt when no cookie is set' do
      get "/s/#{link.id}"
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('magic phrase')
    end

    it 'rejects the wrong phrase' do
      post "/s/#{link.id}/unlock", params: { phrase: 'wrong-phrase-here' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'accepts the right phrase and redirects to the share' do
      post "/s/#{link.id}/unlock", params: { phrase: 'blau-tiger-berg' }
      expect(response).to redirect_to("/s/#{link.id}")
    end

    it 'revokes a prior unlock once the phrase is regenerated' do
      post "/s/#{link.id}/unlock", params: { phrase: 'blau-tiger-berg' }
      get "/s/#{link.id}"
      expect(response).to have_http_status(:ok)

      link.update!(magic_phrase: 'fresh-phrase-here')
      get "/s/#{link.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
