# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculatePerTrackerTracksJob do
  describe 'no argument: enqueueing pending users' do
    let(:user_with_nil_tracker) { create(:user) }
    let(:user_with_tagged_tracker) { create(:user) }
    let(:user_without_tracks) { create(:user) }

    before do
      create(:track, user: user_with_nil_tracker, tracker_id: nil)
      create(:track, user: user_with_tagged_tracker, tracker_id: 'iphone')
    end

    it 'enqueues only users with at least one NULL tracker_id track' do
      expect do
        described_class.perform_now
      end.to have_enqueued_job(described_class).with(user_with_nil_tracker.id).exactly(:once)

      expect(described_class).not_to have_been_enqueued.with(user_with_tagged_tracker.id)
      expect(described_class).not_to have_been_enqueued.with(user_without_tracks.id)
    end

    it 'is idempotent: a second run still only enqueues remaining nil-tracker users' do
      described_class.perform_now
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect do
        described_class.perform_now
      end.to have_enqueued_job(described_class).with(user_with_nil_tracker.id).exactly(:once)
    end

    it 'skips entirely when no user has nil tracker tracks' do
      Track.where(tracker_id: nil).update_all(tracker_id: 'backfilled')

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(described_class)
    end
  end

  describe 'with user_id: processing one user' do
    let(:user) { create(:user) }

    it 'runs RecalculateDataJob synchronously when nil-tracker tracks exist' do
      create(:track, user: user, tracker_id: nil)

      expect_any_instance_of(Users::RecalculateDataJob).to receive(:perform).with(user.id)

      described_class.new.perform(user.id)
    end

    it 'skips when no nil-tracker tracks remain (self-healing)' do
      create(:track, user: user, tracker_id: 'iphone')

      expect_any_instance_of(Users::RecalculateDataJob).not_to receive(:perform)

      described_class.new.perform(user.id)
    end

    it 'no-ops when the user has been deleted' do
      expect { described_class.new.perform(-1) }.not_to raise_error
    end
  end
end
