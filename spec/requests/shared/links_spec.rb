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
