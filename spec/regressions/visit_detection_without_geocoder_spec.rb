# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Automatic visit detection without a reverse geocoder', type: :job do
  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
  end

  describe BulkVisitsSuggestingJob do
    let(:start_at) { 1.day.ago.beginning_of_day }
    let(:end_at) { 1.day.ago.end_of_day }
    let(:user) { create(:user) }

    before do
      allow_any_instance_of(Visits::TimeChunks).to receive(:call).and_return([[start_at, end_at]])
      create(:point, user: user)
    end

    it 'schedules VisitSuggestingJob for users with tracked points' do
      described_class.new.perform

      expect(VisitSuggestingJob).to have_been_enqueued.with(
        user_id: user.id, start_at: start_at, end_at: end_at
      )
    end
  end

  describe Visits::RealtimeDebouncer do
    let(:user) { create(:user) }
    let(:redis_key) { "visit_realtime:user:#{user.id}" }

    before do
      Sidekiq.redis { |redis| redis.del(redis_key) }
    end

    it 'schedules VisitSuggestingJob for the user' do
      expect { described_class.new(user.id).trigger }
        .to have_enqueued_job(VisitSuggestingJob).with(hash_including(user_id: user.id))
    end
  end
end
