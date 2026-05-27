# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visits::Redetections', type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  describe 'POST /redetections' do
    it 'enqueues the job and redirects with notice when no cooldown active' do
      expect do
        post visits_redetections_path
      end.to have_enqueued_job(Visits::FullHistoryRedetectJob).with(user.id)

      expect(response).to redirect_to(settings_visits_path)
      expect(flash[:notice]).to match(/queued/i)
    end

    it 'rejects with 429 when within cooldown' do
      user.update!(visits_redetected_at: 30.minutes.ago)

      expect { post visits_redetections_path }.not_to have_enqueued_job(Visits::FullHistoryRedetectJob)
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'requires authentication' do
      sign_out user
      post visits_redetections_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'DELETE /visits/redetections/lock' do
    let(:lock_key) { "tracks:per_user_lock:#{user.id}" }

    before { Sidekiq.redis { |r| r.del(lock_key) } }
    after  { Sidekiq.redis { |r| r.del(lock_key) } }

    it 'clears the current user lock and redirects with notice' do
      Sidekiq.redis { |r| r.set(lock_key, 'stale-token', ex: 3600) }

      delete visits_redetections_lock_path

      expect(Sidekiq.redis { |r| r.exists(lock_key) }).to eq(0)
      expect(response).to redirect_to(settings_visits_path)
      expect(flash[:notice]).to match(/lock cleared/i)
    end

    it 'returns 204 on JSON requests' do
      delete visits_redetections_lock_path, as: :json

      expect(response).to have_http_status(:no_content)
    end

    it 'only clears the current user\'s lock (does not touch other users)' do
      other_user = create(:user)
      other_key = "tracks:per_user_lock:#{other_user.id}"
      Sidekiq.redis { |r| r.set(other_key, 'other-token', ex: 3600) }
      Sidekiq.redis { |r| r.set(lock_key, 'my-token', ex: 3600) }

      delete visits_redetections_lock_path

      expect(Sidekiq.redis { |r| r.exists(lock_key) }).to eq(0)
      expect(Sidekiq.redis { |r| r.get(other_key) }).to eq('other-token')

      Sidekiq.redis { |r| r.del(other_key) }
    end

    it 'requires authentication' do
      sign_out user
      delete visits_redetections_lock_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
