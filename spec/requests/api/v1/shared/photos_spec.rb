# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Shared::Photos', type: :request do
  let(:owner) { create(:user) }
  let(:trip)  { create(:trip, user: owner) }

  context 'when show_photos is false' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => false })
    end

    it 'returns empty array on index regardless of integration' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'returns 404 for thumbnail requests' do
      get "/api/v1/shared/#{link.id}/photos/foo/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when show_photos is true but owner has no integration' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end

    it 'returns empty array' do
      get "/api/v1/shared/#{link.id}/photos"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end
end
