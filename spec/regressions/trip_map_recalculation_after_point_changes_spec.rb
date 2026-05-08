# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Manual recalculation of a trip after underlying points change',
               type: :request do
  let(:user) { create(:user) }

  let!(:trip) do
    create(:trip,
           user: user,
           started_at: DateTime.new(2024, 11, 27, 12, 0, 0),
           ended_at: DateTime.new(2024, 11, 27, 14, 0, 0),
           distance: 130_362,
           path: 'LINESTRING(13.0 52.0, 13.5 52.5, 14.0 53.0)',
           visited_countries: ['Germany'])
  end

  before do
    allow_any_instance_of(Trip).to receive(:photo_previews).and_return([])
    allow_any_instance_of(Trip).to receive(:photo_sources).and_return([])
    sign_in user
  end

  describe 'POST /trips/:id/recalculate' do
    it 'enqueues Trips::CalculateAllJob with the trip id' do
      expect do
        post recalculate_trip_path(trip)
      end.to have_enqueued_job(Trips::CalculateAllJob).with(trip.id, anything)
    end

    it 'redirects back to the trip page with a notice' do
      post recalculate_trip_path(trip)

      expect(response).to redirect_to(trip_path(trip))
      follow_redirect!
      expect(flash[:notice]).to match(/recalculat/i)
    end

    it 'remains scoped to the current user' do
      other_user = create(:user)
      foreign_trip = create(:trip, user: other_user, path: nil)

      expect do
        post recalculate_trip_path(foreign_trip)
      end.not_to have_enqueued_job(Trips::CalculateAllJob)
    end
  end

  describe 'GET /trips/:id with all cached fields populated' do
    it 'does not auto-enqueue CalculateAllJob' do
      expect { get trip_path(trip) }.not_to have_enqueued_job(Trips::CalculateAllJob)
    end
  end
end
