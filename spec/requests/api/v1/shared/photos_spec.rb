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

  context 'when show_photos is true and the trip has photos' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id,
                           settings: { 'show_photos' => true })
    end
    let(:trip_photos) { [{ id: 'asset-1', source: 'immich', latitude: 52.0, longitude: 13.0 }] }

    before do
      allow(Trips::Photos).to receive(:new).and_return(instance_double(Trips::Photos, call: trip_photos))
    end

    it 'serves thumbnails for photos belonging to the trip' do
      upstream = instance_double(HTTParty::Response, success?: true, body: 'jpeg-bytes')
      allow(Photos::Thumbnail).to receive(:new).with(owner, 'immich', 'asset-1').and_return(
        instance_double(Photos::Thumbnail, call: upstream)
      )

      get "/api/v1/shared/#{link.id}/photos/asset-1/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('jpeg-bytes')
    end

    it 'returns 404 for photo ids outside the trip without contacting the integration' do
      expect(Photos::Thumbnail).not_to receive(:new)

      get "/api/v1/shared/#{link.id}/photos/foreign-asset/thumbnail", params: { source: 'immich' }
      expect(response).to have_http_status(:not_found)
    end
  end
end
