# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::RealtimeDebouncer do
  let(:user) { create(:user) }
  let(:debouncer) { described_class.new(user.id) }
  let(:redis_key) { "visit_realtime:user:#{user.id}" }

  before do
    Sidekiq.redis { |r| r.del(redis_key) }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
  end

  describe '#trigger' do
    context 'when reverse geocoding is disabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      end

      it 'does not enqueue VisitSuggestingJob' do
        expect { debouncer.trigger }.not_to have_enqueued_job(VisitSuggestingJob)
      end

      it 'does not set a Redis key' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          expect(redis.exists(redis_key)).to eq(0)
        end
      end
    end

    context 'when the user has disabled visit suggestions' do
      before do
        user.update!(settings: user.settings.merge('visits_suggestions_enabled' => 'false'))
      end

      it 'does not enqueue VisitSuggestingJob' do
        expect { debouncer.trigger }.not_to have_enqueued_job(VisitSuggestingJob)
      end

      it 'does not set a Redis key' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          expect(redis.exists(redis_key)).to eq(0)
        end
      end
    end

    context 'when the user no longer exists' do
      let(:debouncer) { described_class.new(0) }

      it 'does not enqueue VisitSuggestingJob' do
        expect { debouncer.trigger }.not_to have_enqueued_job(VisitSuggestingJob)
      end
    end

    context 'when called for the first time' do
      it 'sets the Redis key' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          expect(redis.exists(redis_key)).to eq(1)
        end
      end

      it 'schedules a VisitSuggestingJob for this user' do
        expect { debouncer.trigger }.to have_enqueued_job(VisitSuggestingJob)
          .with(hash_including(user_id: user.id))
      end

      it 'schedules the job with a delay' do
        debouncer.trigger

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end

        expect(job['scheduled_at']).to be_present
      end

      it 'covers a recent lookback window' do
        debouncer.trigger

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end
        args = job['arguments'].first

        start_at = Time.zone.parse(args['start_at'])
        end_at = Time.zone.parse(args['end_at'])

        expect(end_at - start_at).to be_within(1.minute).of(described_class::LOOKBACK_WINDOW)
      end
    end

    context 'when called multiple times in quick succession' do
      it 'only schedules one job' do
        3.times { debouncer.trigger }

        jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end

        expect(jobs.size).to eq(1)
      end

      it 'extends the Redis key TTL' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          initial_ttl = redis.ttl(redis_key)
          sleep 0.1
          debouncer.trigger
          new_ttl = redis.ttl(redis_key)

          expect(new_ttl).to be >= initial_ttl - 1
        end
      end
    end

    context 'with different users' do
      let(:other_user) { create(:user) }
      let(:other_debouncer) { described_class.new(other_user.id) }

      it 'schedules separate jobs for each user' do
        debouncer.trigger
        other_debouncer.trigger

        jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end

        expect(jobs.size).to eq(2)

        user_ids = jobs.map { |j| j['arguments'].first['user_id'] }
        expect(user_ids).to contain_exactly(user.id, other_user.id)
      end
    end

    context 'when VisitSuggestingJob.perform_later raises' do
      let(:configured_job) { instance_double(ActiveJob::ConfiguredJob) }

      before do
        allow(VisitSuggestingJob).to receive(:set).and_return(configured_job)
        allow(configured_job).to receive(:perform_later)
          .and_raise(StandardError, 'queue down')
      end

      it 'removes the Redis key so the next call can re-enqueue' do
        expect { debouncer.trigger }.to raise_error(StandardError, 'queue down')

        Sidekiq.redis do |redis|
          expect(redis.exists(redis_key)).to eq(0)
        end
      end
    end
  end

  describe '#clear' do
    it 'removes the Redis key' do
      debouncer.trigger

      Sidekiq.redis do |redis|
        expect(redis.exists(redis_key)).to eq(1)
      end

      debouncer.clear

      Sidekiq.redis do |redis|
        expect(redis.exists(redis_key)).to eq(0)
      end
    end
  end

  describe 'post-fire re-arm contract' do
    # REDIS_KEY_TTL (10 min) > DEBOUNCE_DELAY (5 min), so without intervention
    # the key blocks re-arm for 5 minutes after the job fires. The fix is to
    # have VisitSuggestingJob#perform clear the key at start when invoked with
    # realtime: true.

    it 'enqueues VisitSuggestingJob with realtime: true on first trigger' do
      debouncer.trigger

      job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |j| j['job_class'] == 'VisitSuggestingJob' }
      args = job['arguments'].first

      expect(args).to include('realtime' => true)
    end

    it 'allows a new job to be enqueued after the previous realtime job fires' do
      # First trigger arms the debouncer.
      debouncer.trigger
      expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(1)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      # Simulate the job firing with realtime: true — must clear the debounce key
      # (clearing happens at the START of perform, see VisitSuggestingJob).
      allow_any_instance_of(Visits::Suggest).to receive(:call).and_return([])
      VisitSuggestingJob.new.perform(
        user_id: user.id,
        start_at: 1.hour.ago.iso8601,
        end_at: Time.current.iso8601,
        realtime: true
      )

      # Key cleared, ready to re-arm.
      expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(0)

      # Second trigger after fire enqueues a fresh job.
      expect { debouncer.trigger }.to change {
        ActiveJob::Base.queue_adapter.enqueued_jobs.count { |j| j['job_class'] == 'VisitSuggestingJob' }
      }.by(1)
    end

    it 'does not clear the realtime key when perform is invoked WITHOUT realtime: true' do
      debouncer.trigger
      expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(1)

      # Bulk / import path — no realtime kwarg.
      allow_any_instance_of(Visits::Suggest).to receive(:call).and_return([])
      VisitSuggestingJob.new.perform(
        user_id: user.id,
        start_at: 1.hour.ago.iso8601,
        end_at: Time.current.iso8601
      )

      # Key NOT cleared (still in the debounce window).
      expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(1)
    end
  end
end
