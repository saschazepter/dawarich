# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared::OgImages', type: :request do
  let(:link) { create(:shared_link) }

  describe 'GET /s/:id/og.html' do
    around do |example|
      original = ENV['OG_RENDER_TOKEN']
      ENV['OG_RENDER_TOKEN'] = 'spec-token-here'
      example.run
    ensure
      ENV['OG_RENDER_TOKEN'] = original
    end

    it 'returns 404 without the render token header' do
      get "/s/#{link.id}/og.html"
      expect(response).to have_http_status(:not_found)
    end

    it 'renders the og snapshot with the correct token' do
      get "/s/#{link.id}/og.html", headers: { 'X-OG-Render-Token' => 'spec-token-here' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(link.name)
    end

    context 'for a timeline share' do
      let(:link) do
        create(:shared_link, resource_type: :timeline, resource_id: nil,
                             settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                             name: 'Timeline: 2026-04-01 → 2026-04-14',
                             autobuild_trip: false)
      end

      it 'renders the OG snapshot HTML with timeline title + date range' do
        get "/s/#{link.id}/og.html", headers: { 'X-OG-Render-Token' => 'spec-token-here' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Timeline')
        expect(response.body).to include('April')
      end
    end
  end

  describe 'GET /s/:id/og.png' do
    it 'redirects to the brand default when no image is attached' do
      get "/s/#{link.id}/og.png"
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('og_default')
    end

    it 'serves the brand default for phrase-protected links instead of the rendered image' do
      protected_link = create(:shared_link, :with_phrase, og_image_state: :ready)
      protected_link.og_image.attach(io: StringIO.new('PNG'.b), filename: 'og.png', content_type: 'image/png')
      get "/s/#{protected_link.id}/og.png"
      expect(response.location).to include('og_default')
    end
  end

  describe 'GET /s/:id/og.html for a phrase-protected link' do
    let(:link) { create(:shared_link, :with_phrase) }

    around do |example|
      original = ENV['OG_RENDER_TOKEN']
      ENV['OG_RENDER_TOKEN'] = 'spec-token-here'
      example.run
    ensure
      ENV['OG_RENDER_TOKEN'] = original
    end

    it 'masks the name and dates' do
      get "/s/#{link.id}/og.html", headers: { 'X-OG-Render-Token' => 'spec-token-here' }
      expect(response.body).to include('Private share')
      expect(response.body).not_to include(link.name)
    end
  end
end
