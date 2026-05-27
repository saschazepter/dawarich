# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /visits/:id/select_place (web)' do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:visit) { create(:visit, user: user, area: nil, place: nil) }

  let(:photon_payload) do
    {
      photon: {
        name: 'Café Bravo',
        latitude: 52.5126,
        longitude: 13.4012,
        osm_id: 1_234_567,
        city: 'Berlin',
        country: 'Germany'
      }
    }
  end

  before { sign_in user }

  it 'assigns the place to the visit and responds with turbo_stream' do
    expect do
      post select_place_visit_path(visit), params: photon_payload, as: :turbo_stream
    end.to change { visit.reload.place_id }.from(nil).to(an_instance_of(Integer))

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream])
  end

  it 'returns 404 for a visit not owned by the current user' do
    other_visit = create(:visit, user: other, area: nil)

    post select_place_visit_path(other_visit), params: photon_payload, as: :turbo_stream

    expect(response).to have_http_status(:not_found)
  end

  it 'returns a turbo_stream error flash for out-of-range latitude' do
    payload = photon_payload.deep_dup
    payload[:photon][:latitude] = 99.0

    post select_place_visit_path(visit), params: payload, as: :turbo_stream

    expect(response.body).to include('latitude out of range')
  end
end
