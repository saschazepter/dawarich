# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Posters', type: :request do
  let(:user) { create(:user) }

  before do
    Flipper.enable(:posters)
    sign_in user
  end

  describe 'POST /posters' do
    let(:poster_attributes) do
      {
        name: 'Berlin', lat: 52.52, lon: 13.405, distance: 6000,
        theme: 'blueprint', start_at: '2026-04-01T00:00', end_at: '2026-04-30T23:59',
        source: 'tracks'
      }
    end

    it 'creates a poster with source in settings and enqueues generation' do
      expect do
        post posters_path, params: { poster: poster_attributes }, as: :turbo_stream
      end.to have_enqueued_job(Posters::CreateJob)

      poster = user.posters.last
      expect(poster.name).to eq('Berlin')
      expect(poster.settings['source']).to eq('tracks')
      expect(response.body).to include('poster-gallery-list')
    end

    it 'persists route fill and opacity into settings' do
      post posters_path, params: { poster: poster_attributes.merge(route_fill: '1', route_opacity: '40') },
                         as: :turbo_stream

      settings = user.posters.last.settings
      expect(settings['route_fill']).to eq('1')
      expect(settings['route_opacity']).to eq('40')
    end

    it 'falls back to a default name' do
      post posters_path, params: { poster: poster_attributes.merge(name: '') }, as: :turbo_stream

      expect(user.posters.last.name).to eq('My Poster')
    end

    it 'redirects when posters are not enabled' do
      Flipper.disable(:posters)

      post posters_path, params: { poster: poster_attributes }

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'DELETE /posters/:id' do
    it 'destroys the poster and removes its card' do
      poster = create(:poster, user: user)

      delete poster_path(poster), as: :turbo_stream

      expect(user.posters.count).to eq(0)
      expect(response.body).to include("poster_#{poster.id}")
    end

    it 'does not destroy other users posters' do
      poster = create(:poster)

      delete poster_path(poster), as: :turbo_stream

      expect(response).to have_http_status(:not_found)
      expect(Poster.count).to eq(1)
    end
  end

  describe 'removed endpoints' do
    include RSpec::Rails::Matchers::RoutingMatchers

    let(:routes) { Rails.application.routes }

    it 'no longer routes GET /posters' do
      expect(get: '/posters').not_to be_routable
    end

    it 'no longer routes GET /posters/preview_track' do
      expect(get: '/posters/preview_track').not_to be_routable
    end
  end
end
