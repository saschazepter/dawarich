# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Videos', type: :request do
  let(:user) { create(:user, :pro_plan) }
  let(:track) { create(:track, user:) }

  before do
    sign_in user
    ENV['VIDEO_SERVICE_URL'] = 'http://dawarich_video:3100'
    DawarichSettings.instance_variable_set(:@video_service_enabled, nil)
  end

  after do
    ENV.delete('VIDEO_SERVICE_URL')
    DawarichSettings.instance_variable_set(:@video_service_enabled, nil)
  end

  describe 'GET /videos' do
    it 'renders the index for a Pro user' do
      get videos_path
      expect(response).to have_http_status(:ok)
    end

    it 'redirects when video service is disabled' do
      ENV.delete('VIDEO_SERVICE_URL')
      DawarichSettings.instance_variable_set(:@video_service_enabled, nil)
      get videos_path
      expect(response).to have_http_status(:redirect)
    end

    it 'redirects Lite users' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      lite = create(:user, :lite_plan)
      sign_in lite
      get videos_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST /videos' do
    it 'creates a Video for a valid track_id' do
      expect do
        post videos_path, params: { track_id: track.id },
                          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end.to change(Video, :count).by(1)
      expect(response).to have_http_status(:ok)
      created = Video.last
      expect(created.user).to eq(user)
      expect(created.track).to eq(track)
      expect(created.start_at.to_i).to eq(track.start_at.to_i)
    end

    it 'creates a Video for a valid date' do
      expect do
        post videos_path, params: { date: '2026-04-01' },
                          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end.to change(Video, :count).by(1)
      created = Video.last
      expect(created.track_id).to be_nil
      expect(created.start_at.to_date).to eq(Date.parse('2026-04-01'))
    end

    it 'rejects a track that does not belong to the user' do
      other = create(:track, user: create(:user))
      expect do
        post videos_path, params: { track_id: other.id },
                          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end.not_to change(Video, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /videos/:id' do
    it 'destroys the video' do
      video = create(:video, user:, track:)
      expect do
        delete video_path(video),
               headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end.to change(Video, :count).by(-1)
    end
  end
end
