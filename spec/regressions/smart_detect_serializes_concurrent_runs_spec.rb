# frozen_string_literal: true

require 'rails_helper'

# Mirrors spec/regressions/full_history_redetect_serializes_concurrent_runs_spec.rb.
# Cloud disables PG advisory locks (DATABASE_ADVISORY_LOCKS=false), so SmartDetect
# now wraps in Tracks::PerUserLock (Redis SETNX). This regression lock the
# behaviour in: a second concurrent SmartDetect.call for the same user must
# raise AcquisitionTimeout rather than silently double-clustering.
RSpec.describe 'Visits::SmartDetect serializes concurrent runs' do
  let(:user) { create(:user) }
  let(:base_ts) { 1_700_000_000 }
  let(:lock_key) { "tracks:per_user_lock:#{user.id}" }

  before do
    Sidekiq.redis { |r| r.del(lock_key) }
    3.times do |i|
      create(:point, user: user,
                     latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
    end
  end

  after { Sidekiq.redis { |r| r.del(lock_key) } }

  it 'raises AcquisitionTimeout when another holder already owns the user lock' do
    stub_const('Visits::SmartDetect::LOCK_ACQUIRE_TIMEOUT', 0.2)
    Sidekiq.redis { |r| r.set(lock_key, 'other-holder', ex: 60) }

    expect do
      Visits::SmartDetect.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call
    end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout, /user_id=#{user.id}/)

    # The other holder's lock value MUST remain intact (token-verified release).
    remaining = Sidekiq.redis { |r| r.get(lock_key) }
    expect(remaining).to eq('other-holder')
  end

  it 'releases the lock after a successful run' do
    Visits::SmartDetect.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call

    expect(Sidekiq.redis { |r| r.exists(lock_key) }).to eq(0)
  end

  it 'is reentrant: nested SmartDetect call inside the same thread does not deadlock' do
    # Simulates FullHistoryRedetectJob holding the per-user lock and then
    # calling SmartDetect — the inner call must yield without re-acquiring.
    inner_completed = false

    Tracks::PerUserLock.with_user_lock(user.id, timeout: 5) do
      result = Visits::SmartDetect.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call
      inner_completed = true
      expect(result).to be_an(Array)
    end

    expect(inner_completed).to be(true)
  end

  it 'short-circuits to AcquisitionTimeout quickly when configured with a short timeout' do
    Sidekiq.redis { |r| r.set(lock_key, 'other-holder', ex: 60) }
    stub_const('Visits::SmartDetect::LOCK_ACQUIRE_TIMEOUT', 0.2)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect do
      Visits::SmartDetect.new(user, start_at: base_ts - 1, end_at: base_ts + 600).call
    end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(elapsed).to be < 2.0
  end
end
