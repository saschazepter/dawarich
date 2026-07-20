# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared achievements' do
  describe 'GET /shared/achievements/:uuid' do
    let(:user) { create(:user) }
    let!(:exploration) do
      create(:achievement_progress, user: user, achievement_key: 'exploration',
                                    state: { 'earned' => { 'DE-BY' => '2026-07-01T10:00:00Z' } })
    end
    let(:progress) do
      create(
        :achievement_progress,
        user: user,
        achievement_key: 'country_de',
        sharing_enabled: true,
        sharing_uuid: SecureRandom.uuid
      )
    end

    it 'renders the badge page without authentication' do
      get shared_achievement_path(progress.sharing_uuid)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Germany Explorer')
      expect(response.body).to include('1/16')
    end

    it 'redirects when sharing is disabled' do
      progress.update!(sharing_enabled: false)

      get shared_achievement_path(progress.sharing_uuid)

      expect(response).to redirect_to(root_path)
    end

    it 'redirects for an unknown uuid' do
      get shared_achievement_path(SecureRandom.uuid)

      expect(response).to redirect_to(root_path)
    end
  end
end
