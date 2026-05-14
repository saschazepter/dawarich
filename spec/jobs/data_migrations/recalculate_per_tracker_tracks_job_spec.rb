# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculatePerTrackerTracksJob do
  let(:user_with_tracks) { create(:user) }
  let(:user_without_tracks) { create(:user) }

  before do
    create(:track, user: user_with_tracks, tracker_id: 'iphone')
  end

  it 'enqueues a Users::RecalculateDataJob only for users with tracks' do
    expect do
      described_class.perform_now
    end.to have_enqueued_job(Users::RecalculateDataJob).with(user_with_tracks.id).exactly(:once)

    expect(Users::RecalculateDataJob).not_to have_been_enqueued.with(user_without_tracks.id)
  end

  it 'sets a flag in user settings so a re-run skips already-queued users' do
    described_class.perform_now

    user_with_tracks.reload
    expect(user_with_tracks.settings[described_class::FLAG_KEY]).to be_present
  end

  it 'is idempotent: a second run does not re-enqueue the same user' do
    described_class.perform_now
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(Users::RecalculateDataJob)
  end
end
