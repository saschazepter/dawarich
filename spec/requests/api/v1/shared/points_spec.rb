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

    it 'stops honoring a prior unlock cookie after the phrase is regenerated' do
      link.update!(magic_phrase: 'open-sesame-now')
      post "/s/#{link.id}/unlock", params: { phrase: 'open-sesame-now' }
      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:ok)

      link.update!(magic_phrase: 'totally-new-phrase')
      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'excludes points inside the owner privacy zones' do
      create(:point, user: owner, timestamp: Time.utc(2026, 4, 6).to_i, latitude: 52.0, longitude: 13.0)
      home = create(:place, user: owner, latitude: 52.0, longitude: 13.0)
      tag = create(:tag, user: owner, privacy_radius_meters: 500)
      create(:tagging, tag: tag, taggable: home)

      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first[1]).to eq(60.0)
    end

    it 'bounds the payload to MAX_POINTS via SQL stride sampling' do
      stub_const('Api::V1::Shared::PointsController::MAX_POINTS', 1)
      create(:point, user: owner, timestamp: Time.utc(2026, 4, 6).to_i, latitude: 60.0, longitude: 10.0)
      create(:point, user: owner, timestamp: Time.utc(2026, 4, 7).to_i, latitude: 60.0, longitude: 10.0)

      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first.map { |v| v.is_a?(Numeric) }).to all(be true)
    end
  end

  context 'for a track share' do
    let(:track) do
      create(:track, user: owner, start_at: Time.utc(2026, 4, 1), end_at: Time.utc(2026, 4, 14))
    end
    let(:link) { create(:shared_link, user: owner, resource_type: :track, resource_id: track.id) }

    before do
      create(:point, user: owner, track: track, timestamp: Time.utc(2026, 4, 5).to_i, latitude: 60.0, longitude: 10.0)
      create(:point, user: owner, timestamp: Time.utc(2026, 4, 6).to_i, latitude: 61.0, longitude: 11.0)
    end

    it 'returns only the points belonging to the track' do
      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body.size).to eq(1)
      expect(body.first[1]).to eq(60.0)
    end

    it 'excludes track points inside the owner privacy zones' do
      create(:point, user: owner, track: track, timestamp: Time.utc(2026, 4, 7).to_i, latitude: 52.0, longitude: 13.0)
      home = create(:place, user: owner, latitude: 52.0, longitude: 13.0)
      tag = create(:tag, user: owner, privacy_radius_meters: 500)
      create(:tagging, tag: tag, taggable: home)

      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first[1]).to eq(60.0)
    end

    it 'returns [] when the track no longer exists' do
      track.destroy
      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'returns 401 when phrase required but not unlocked' do
      link.update!(magic_phrase: 'open-sesame-now')
      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'for a live share' do
    let(:link) { create(:shared_link, :live, user: owner) }

    it 'returns the latest point as a single [lon, lat, ts] tuple' do
      create(:point, user: owner, timestamp: 10.minutes.ago.to_i, latitude: 60.0, longitude: 10.0)
      create(:point, user: owner, timestamp: 2.minutes.ago.to_i, latitude: 61.0, longitude: 11.0)

      get "/api/v1/shared/#{link.id}/points"
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body.size).to eq(1)
      expect(body.first[0]).to be_within(0.0001).of(11.0)
      expect(body.first[1]).to be_within(0.0001).of(61.0)
    end

    it 'returns [] when the latest point is older than the freshness threshold' do
      create(:point, user: owner, timestamp: 30.minutes.ago.to_i, latitude: 60.0, longitude: 10.0)

      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'returns [] when the user has no points' do
      get "/api/v1/shared/#{link.id}/points"
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'returns [] when the latest point is inside a privacy zone (masked)' do
      create(:point, user: owner, timestamp: 1.minute.ago.to_i, latitude: 52.0, longitude: 13.0)
      home = create(:place, user: owner, latitude: 52.0, longitude: 13.0)
      tag = create(:tag, user: owner, privacy_radius_meters: 500)
      create(:tagging, tag: tag, taggable: home)

      get "/api/v1/shared/#{link.id}/points"
      expect(JSON.parse(response.body)).to eq([])
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

    it 'returns [] when settings has unparseable dates' do
      link.update_columns(settings: { 'start_date' => 'not-a-date', 'end_date' => 'also-bogus' })
      get "/api/v1/shared/#{link.id}/points"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end
end
