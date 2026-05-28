# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Shared::Points', type: :request do
  let(:owner) { create(:user) }

  context 'for a trip share' do
    let(:trip) do
      create(:trip, user: owner,
                    started_at: Time.utc(2026, 4, 1),
                    ended_at: Time.utc(2026, 4, 14))
    end
    let(:link) { create(:shared_link, user: owner, resource_type: :trip, resource_id: trip.id) }

    before do
      create(:point, user: owner, timestamp: Time.utc(2026, 4, 5).to_i, latitude: 60.0, longitude: 10.0)
      create(:point, user: owner, timestamp: Time.utc(2026, 3, 1).to_i, latitude: 60.0, longitude: 10.0)
      create(:point, user: owner, timestamp: Time.utc(2026, 6, 1).to_i, latitude: 60.0, longitude: 10.0)
      create(:point, user: create(:user), timestamp: Time.utc(2026, 4, 5).to_i, latitude: 60.0, longitude: 10.0)
    end

    it 'returns only points within the trip date range' do
      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body.size).to eq(1)
    end

    it 'returns [lon, lat, ts] tuples' do
      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      point = body.first
      expect(point).to be_a(Array)
      expect(point.size).to eq(3)
      expect(point[0]).to be_a(Numeric)
      expect(point[1]).to be_a(Numeric)
      expect(point[2]).to be_a(Numeric)
    end

    it 'returns 404 for an unknown link' do
      get '/api/v1/shared/00000000-0000-0000-0000-000000000000/points'
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 when phrase required but not unlocked' do
      link.update!(magic_phrase: 'open-sesame-now')
      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'for a timeline share' do
    let(:link) do
      create(:shared_link, user: owner, resource_type: :timeline, resource_id: nil,
                           settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                           autobuild_trip: false)
    end

    before do
      create(:point, user: owner, timestamp: Time.utc(2026, 4, 5).to_i,  latitude: 60.0, longitude: 10.0)
      create(:point, user: owner, timestamp: Time.utc(2026, 3, 1).to_i,  latitude: 60.0, longitude: 10.0)
      create(:point, user: owner, timestamp: Time.utc(2026, 6, 1).to_i,  latitude: 60.0, longitude: 10.0)
      create(:point, user: create(:user), timestamp: Time.utc(2026, 4, 5).to_i, latitude: 60.0, longitude: 10.0)
    end

    it 'returns only points within the timeline date range, scoped to owner' do
      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body.size).to eq(1)
    end

    it 'returns end_date inclusive (end of day)' do
      create(:point, user: owner, timestamp: Time.utc(2026, 4, 14, 23, 30).to_i, latitude: 60.0, longitude: 10.0)
      get "/api/v1/shared/#{link.id}/points"
      expect(JSON.parse(response.body).size).to eq(2)
    end
  end
end
