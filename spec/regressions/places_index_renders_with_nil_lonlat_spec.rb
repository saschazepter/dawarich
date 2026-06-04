# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Places with nil lonlat', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def place_with_nil_lonlat
    place = build(:place, user: user, latitude: 52.52, longitude: 13.405)
    place.save!(validate: false)
    place.update_column(:lonlat, nil)
    place
  end

  describe Place do
    it 'returns the latitude column value when lonlat is nil' do
      place = place_with_nil_lonlat

      expect(place.lat).to eq(52.52)
    end

    it 'returns the longitude column value when lonlat is nil' do
      place = place_with_nil_lonlat

      expect(place.lon).to eq(13.405)
    end
  end

  describe 'GET /places' do
    it 'renders successfully when a place has nil lonlat' do
      place_with_nil_lonlat

      get places_url

      expect(response).to have_http_status(:ok)
    end
  end
end
