# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Videos callback', type: :request do
  let(:user)  { create(:user) }
  let(:track) { create(:track, user:) }
  let(:video) { create(:video, user:, track:, status: :processing) }
  let(:token) { Videos::CallbackToken.generate(video.id, video.callback_nonce) }

  let(:mp4_path) { Rails.root.join('spec/fixtures/files/sample.mp4') }
  let(:upload) { fixture_file_upload(mp4_path, 'video/mp4') }

  describe 'POST /api/v1/videos/:id/callback' do
    it 'attaches the file and marks completed when status is completed' do
      post "/api/v1/videos/#{video.id}/callback",
           params: { token:, status: 'completed', file: upload }

      expect(response).to have_http_status(:ok)
      expect(video.reload.status).to eq('completed')
      expect(video.file).to be_attached
      expect(Notification.where(user:).count).to eq(1)
    end

    it 'rejects an invalid token with 401' do
      post "/api/v1/videos/#{video.id}/callback",
           params: { token: 'wrong', status: 'completed', file: upload }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a non-video MIME with 422' do
      txt = Rails.root.join('spec/fixtures/files/notavideo.txt')
      post "/api/v1/videos/#{video.id}/callback",
           params: { token:, status: 'completed',
                     file: fixture_file_upload(txt, 'text/plain') }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects an empty file with 422' do
      empty = Rails.root.join('spec/fixtures/files/empty.mp4')
      post "/api/v1/videos/#{video.id}/callback",
           params: { token:, status: 'completed',
                     file: fixture_file_upload(empty, 'video/mp4') }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 409 if the video is already terminal' do
      video.update!(status: :completed)
      post "/api/v1/videos/#{video.id}/callback",
           params: { token:, status: 'completed', file: upload }
      expect(response).to have_http_status(:conflict)
    end

    it 'sets failed and stores error_message when status is failed' do
      post "/api/v1/videos/#{video.id}/callback",
           params: { token:, status: 'failed', error_message: 'render crashed' }
      expect(response).to have_http_status(:ok)
      expect(video.reload.status).to eq('failed')
      expect(video.error_message).to eq('render crashed')
    end

    it 'returns 401 for an unknown video id' do
      post '/api/v1/videos/0/callback', params: { token: 'x', status: 'completed' }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
