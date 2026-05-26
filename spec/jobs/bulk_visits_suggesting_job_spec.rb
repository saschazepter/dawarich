# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkVisitsSuggestingJob, type: :job do
  describe '#perform' do
    let(:start_at) { 1.day.ago.beginning_of_day }
    let(:end_at) { 1.day.ago.end_of_day }
    let(:user) { create(:user) }
    let(:inactive_user) { create(:user, :inactive) }
    let(:user_with_points) { create(:user) }
    let(:time_chunks) { [[start_at, end_at]] }

    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      allow_any_instance_of(Visits::TimeChunks).to receive(:call).and_return(time_chunks)
      create(:point, user: user_with_points)
    end

    it 'does nothing if reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

      expect { described_class.perform_now }.not_to have_enqueued_job(VisitSuggestingJob)
    end

    it 'schedules jobs only for active users with tracked points' do
      described_class.perform_now

      expect(VisitSuggestingJob).to have_been_enqueued.with(
        user_id: user_with_points.id,
        start_at: time_chunks.first.first,
        end_at: time_chunks.first.last
      )

      expect(VisitSuggestingJob).not_to have_been_enqueued.with(
        user_id: user.id,
        start_at: anything,
        end_at: anything
      )

      expect(VisitSuggestingJob).not_to have_been_enqueued.with(
        user_id: inactive_user.id,
        start_at: anything,
        end_at: anything
      )
    end

    it 'handles multiple time chunks when range exceeds the TimeChunks threshold' do
      long_start = 60.days.ago.beginning_of_day
      long_end = Time.current.end_of_day
      chunks = [
        [long_start.to_datetime, long_start.end_of_year.to_datetime],
        [long_start.next_year.beginning_of_year.to_datetime, long_end.to_datetime]
      ]
      allow_any_instance_of(Visits::TimeChunks).to receive(:call).and_return(chunks)

      active_users_mock = double('ActiveRecord::Relation')
      allow(User).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:where).with(id: []).and_return(active_users_mock)
      allow(active_users_mock).to receive(:find_each).and_yield(user_with_points)

      described_class.perform_now(start_at: long_start, end_at: long_end)

      chunks.each do |chunk|
        expect(VisitSuggestingJob).to have_been_enqueued.with(
          user_id: user_with_points.id,
          start_at: chunk.first,
          end_at: chunk.last
        )
      end
    end

    context 'with a range no longer than 32 days (daily cron path)' do
      it 'bypasses Visits::TimeChunks and enqueues a single job per user covering the full range' do
        expect(Visits::TimeChunks).not_to receive(:new)

        described_class.perform_now

        expect(VisitSuggestingJob).to have_been_enqueued.with(
          user_id: user_with_points.id,
          start_at: start_at.to_datetime,
          end_at: end_at.to_datetime
        ).exactly(:once)
      end

      it 'does not stretch a yesterday-only run to the end of the year' do
        # Regression: TimeChunks.call would return [start..start.end_of_year] for
        # same-year ranges (time_chunks.rb:15), which then expanded into a daily
        # loop running from yesterday through Dec 31 inside VisitSuggestingJob.
        expect(Visits::TimeChunks).not_to receive(:new)

        expect { described_class.perform_now }.to change {
          ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j['job_class'] == 'VisitSuggestingJob' }
        }.by(1)
      end
    end

    context 'with a range longer than 32 days (multi-month backfill path)' do
      it 'invokes Visits::TimeChunks to split the range' do
        long_start = 60.days.ago.beginning_of_day
        long_end = Time.current.end_of_day
        chunks = [[long_start.to_datetime, long_end.to_datetime]]
        time_chunks_instance = instance_double(Visits::TimeChunks, call: chunks)
        allow(Visits::TimeChunks).to receive(:new)
          .with(start_at: long_start.to_datetime, end_at: long_end.to_datetime)
          .and_return(time_chunks_instance)

        described_class.perform_now(start_at: long_start, end_at: long_end)

        expect(Visits::TimeChunks).to have_received(:new)
          .with(start_at: long_start.to_datetime, end_at: long_end.to_datetime)
      end
    end

    it 'only processes specified users when user_ids is provided' do
      create(:point, user: user)

      described_class.perform_now(user_ids: [user.id])

      expect(VisitSuggestingJob).to have_been_enqueued.with(
        user_id: user.id,
        start_at: time_chunks.first.first,
        end_at: time_chunks.first.last
      )

      expect(VisitSuggestingJob).not_to have_been_enqueued.with(
        user_id: user_with_points.id,
        start_at: anything,
        end_at: anything
      )
    end

    it 'uses custom time range when provided' do
      custom_start = 2.days.ago.beginning_of_day
      custom_end = 2.days.ago.end_of_day
      custom_chunks = [[custom_start, custom_end]]

      time_chunks_instance = instance_double(Visits::TimeChunks)
      allow(Visits::TimeChunks).to receive(:new)
        .with(start_at: custom_start, end_at: custom_end)
        .and_return(time_chunks_instance)
      allow(time_chunks_instance).to receive(:call).and_return(custom_chunks)

      active_users_mock = double('ActiveRecord::Relation')
      allow(User).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:where).with(id: []).and_return(active_users_mock)
      allow(active_users_mock).to receive(:find_each).and_yield(user_with_points)

      described_class.perform_now(start_at: custom_start, end_at: custom_end)

      expect(VisitSuggestingJob).to have_been_enqueued.with(
        user_id: user_with_points.id,
        start_at: custom_chunks.first.first,
        end_at: custom_chunks.first.last
      )
    end

    context 'when visits suggestions are disabled' do
      before do
        allow_any_instance_of(Users::SafeSettings).to receive(:visits_suggestions_enabled?).and_return(false)
      end

      it 'does not schedule jobs' do
        expect { described_class.perform_now }.not_to have_enqueued_job(VisitSuggestingJob)
      end
    end
  end
end
