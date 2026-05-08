# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Inline rename of a suggested visit', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'PATCH /visits/:id with only visit[name] on a suggested visit' do
    let!(:nearby_place_a) { create(:place, user:, name: 'Cafe A', latitude: 54.2905, longitude: 13.0948) }
    let!(:nearby_place_b) { create(:place, user:, name: 'Cafe B', latitude: 54.2906, longitude: 13.0949) }
    let(:visit) do
      v = create(:visit, user:, status: :suggested, name: 'Visit')
      v.update!(place: nearby_place_a)
      v
    end

    before do
      create(:place_visit, visit:, place: nearby_place_a)
      create(:place_visit, visit:, place: nearby_place_b)
    end

    it 'sets visit.name to the typed value' do
      patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream

      expect(visit.reload.name).to eq('My Coffee Spot')
    end

    it 'auto-confirms the visit' do
      patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream

      expect(visit.reload.status).to eq('confirmed')
    end

    it 'creates a new user-owned Place from the typed name and links it to the visit' do
      expect do
        patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream
      end.to change(Place, :count).by(1)

      created = user.places.find_by(name: 'My Coffee Spot')
      expect(created).to be_present
      expect(created.user_id).to eq(user.id)
      expect(visit.reload.place_id).to eq(created.id)
    end

    it 'positions the new Place at the visit center' do
      patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream

      created = user.places.find_by(name: 'My Coffee Spot')
      lat, lon = visit.reload.center
      expect(created.latitude.to_f).to be_within(0.0001).of(lat)
      expect(created.longitude.to_f).to be_within(0.0001).of(lon)
    end

    it 'reuses an existing user-owned Place near the visit when the typed name matches' do
      lat, lon = visit.center
      existing = create(:place, user:, name: 'My Coffee Spot', latitude: lat, longitude: lon)

      expect do
        patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.place_id).to eq(existing.id)
    end

    it 'does not reuse another user\'s same-name place near the visit center' do
      lat, lon = visit.center
      other_user = create(:user)
      create(:place, user: other_user, name: 'My Coffee Spot', latitude: lat, longitude: lon)

      expect do
        patch visit_url(visit), params: { visit: { name: 'My Coffee Spot' } }, as: :turbo_stream
      end.to change(Place, :count).by(1)

      created = user.places.find_by(name: 'My Coffee Spot')
      expect(created).to be_present
      expect(created.user_id).to eq(user.id)
    end
  end

  describe 'PATCH /visits/:id with only visit[name] on a confirmed visit' do
    let(:visit) { create(:visit, user:, status: :confirmed, name: 'Old Name') }

    it 'updates the name without creating a Place or changing status' do
      expect do
        patch visit_url(visit), params: { visit: { name: 'Edited Name' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.name).to eq('Edited Name')
      expect(visit.reload.status).to eq('confirmed')
    end
  end

  describe 'PATCH /visits/:id with blank visit[name] on a suggested visit' do
    let(:visit) { create(:visit, user:, status: :suggested, name: 'Original') }

    it 'is a no-op for name and does not auto-confirm or create a Place' do
      expect do
        patch visit_url(visit), params: { visit: { name: '   ' } }, as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.name).to eq('Original')
      expect(visit.reload.status).to eq('suggested')
    end
  end

  describe 'PATCH /visits/:id picker confirm (place_id + status)' do
    let!(:nearby_place) { create(:place, user:, name: 'Cafe A', latitude: 54.2905, longitude: 13.0948) }
    let(:visit) { create(:visit, user:, status: :suggested, name: 'Visit') }

    before { create(:place_visit, visit:, place: nearby_place) }

    it 'still confirms via the picker without creating an extra Place' do
      expect do
        patch visit_url(visit),
              params: { visit: { place_id: nearby_place.id, status: :confirmed } },
              as: :turbo_stream
      end.not_to change(Place, :count)

      expect(visit.reload.place_id).to eq(nearby_place.id)
      expect(visit.reload.status).to eq('confirmed')
      expect(visit.reload.name).to eq('Cafe A')
    end
  end
end
