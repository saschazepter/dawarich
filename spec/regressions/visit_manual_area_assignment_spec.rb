# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Manual area assignment for visits', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }
  let(:area) { create(:area, user: user, name: 'Home', latitude: 52.5, longitude: 13.4, radius: 200) }
  let(:visit) { create(:visit, user: user, name: 'before', place: nil, area: nil) }

  describe 'PATCH /api/v1/visits/:id' do
    let(:auth_headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    it 'persists area_id when the user owns the area' do
      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: area.id } },
            headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(visit.reload.area_id).to eq(area.id)
    end

    it 'updates the visit name to the area name when no name was provided' do
      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: area.id } },
            headers: auth_headers

      expect(visit.reload.name).to eq('Home')
    end

    it 'preserves a user-provided name even when area_id is set' do
      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: area.id, name: 'Custom label' } },
            headers: auth_headers

      expect(visit.reload.name).to eq('Custom label')
    end

    it 'rejects a foreign area with 422' do
      foreign_user = create(:user)
      foreign_area = create(:area, user: foreign_user, name: 'Foreign', latitude: 1.0, longitude: 1.0, radius: 100)

      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: foreign_area.id } },
            headers: auth_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(visit.reload.area_id).to be_nil
    end

    it 'prefers place name over area name when both are provided' do
      place = create(:place, user: user, name: 'Coffee Shop')

      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { place_id: place.id, area_id: area.id } },
            headers: auth_headers

      visit.reload
      expect(visit.place_id).to eq(place.id)
      expect(visit.area_id).to eq(area.id)
      expect(visit.name).to eq('Coffee Shop')
    end

    it 'clears area_id when an empty value is sent' do
      visit.update!(area: area)
      expect(visit.reload.area_id).to eq(area.id)

      patch "/api/v1/visits/#{visit.id}",
            params: { visit: { area_id: '' } },
            headers: auth_headers

      expect(visit.reload.area_id).to be_nil
    end
  end

  describe 'PATCH /visits/:id (web controller)' do
    before { sign_in user }

    it 'persists area_id when the user owns the area' do
      patch "/visits/#{visit.id}",
            params: { visit: { area_id: area.id } }

      expect(visit.reload.area_id).to eq(area.id)
      expect(visit.reload.name).to eq('Home')
    end

    it 'rejects a foreign area' do
      foreign_user = create(:user)
      foreign_area = create(:area, user: foreign_user, name: 'Foreign', latitude: 1.0, longitude: 1.0, radius: 100)

      patch "/visits/#{visit.id}",
            params: { visit: { area_id: foreign_area.id } },
            headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Invalid area')
      expect(visit.reload.area_id).to be_nil
    end

    it 'prefers place name over area name when both are provided' do
      place = create(:place, user: user, name: 'Coffee Shop')

      patch "/visits/#{visit.id}",
            params: { visit: { place_id: place.id, area_id: area.id } }

      visit.reload
      expect(visit.place_id).to eq(place.id)
      expect(visit.area_id).to eq(area.id)
      expect(visit.name).to eq('Coffee Shop')
    end
  end
end
