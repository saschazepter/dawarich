# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Achievements' do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /achievements' do
    context 'when the feature flag is enabled' do
      before { Flipper.enable(:achievements) }
      after { Flipper.disable(:achievements) }

      it 'renders both sets with progress' do
        create(
          :achievement_progress,
          user:, achievement_key: 'explorer_germany',
          state: { 'earned' => { 'DE-BY' => '2026-07-01T10:00:00Z' }, 'dwell' => { 'DE-BY' => 4200 }, 'cursor' => 1 }
        )

        get achievements_path

        expect(response.body).to include('Germany Explorer')
        expect(response.body).to include('USA Explorer')
        expect(response.body).to include('1/16')
        expect(response.body).to include('0/50')
      end

      describe 'PATCH /achievements/:key/toggle_sharing' do
        it 'enables sharing and generates a uuid once' do
          progress = create(:achievement_progress, user:, achievement_key: 'explorer_germany')

          patch toggle_sharing_achievement_path('explorer_germany')
          expect(progress.reload.sharing_enabled).to be(true)
          uuid = progress.sharing_uuid
          expect(uuid).to be_present

          patch toggle_sharing_achievement_path('explorer_germany')
          expect(progress.reload.sharing_enabled).to be(false)
          expect(progress.sharing_uuid).to eq(uuid)
        end

        it 'returns 404 when no progress row exists' do
          patch toggle_sharing_achievement_path('explorer_germany')

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when the feature flag is disabled' do
      it 'redirects to root' do
        get achievements_path

        expect(response).to redirect_to(root_path)
      end
    end
  end
end
