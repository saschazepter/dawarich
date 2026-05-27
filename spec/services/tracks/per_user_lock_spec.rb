# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::PerUserLock do
  let(:user_id) { 1410 }
  let(:redis_key) { "tracks:per_user_lock:#{user_id}" }

  before do
    Sidekiq.redis do |r|
      r.del(redis_key)
      r.del("tracks:per_user_lock:#{user_id + 1}")
    end
  end

  describe '.with_user_lock' do
    it 'yields and returns the block value' do
      result = described_class.with_user_lock(user_id) { :yielded }

      expect(result).to eq(:yielded)
    end

    it 'holds the lock for the duration of the block' do
      observed_during_block = nil

      described_class.with_user_lock(user_id) do
        observed_during_block = Sidekiq.redis { |r| r.exists(redis_key) }
      end

      expect(observed_during_block).to eq(1)
    end

    it 'releases the lock after the block completes' do
      described_class.with_user_lock(user_id) { :ok }

      released = Sidekiq.redis { |r| r.exists(redis_key) }
      expect(released).to eq(0)
    end

    it 'releases the lock when the block raises' do
      expect do
        described_class.with_user_lock(user_id) { raise 'boom' }
      end.to raise_error('boom')

      released = Sidekiq.redis { |r| r.exists(redis_key) }
      expect(released).to eq(0)
    end

    it 'sets a TTL on the lock key so a crashed worker cannot orphan it' do
      lock_ttl = nil

      described_class.with_user_lock(user_id) do
        lock_ttl = Sidekiq.redis { |r| r.ttl(redis_key) }
      end

      expect(lock_ttl).to be > 0
    end

    it 'raises AcquisitionTimeout when another holder owns the lock' do
      Sidekiq.redis { |r| r.set(redis_key, 'other-owner', ex: 60) }

      expect do
        described_class.with_user_lock(user_id, timeout: 0.2) { :never_runs }
      end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout, /user_id=#{user_id}/)
    end

    it 'does not delete a lock held by a different owner' do
      Sidekiq.redis { |r| r.set(redis_key, 'other-owner', ex: 60) }

      expect do
        described_class.with_user_lock(user_id, timeout: 0.1) { :never_runs }
      end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout)

      remaining = Sidekiq.redis { |r| r.get(redis_key) }
      expect(remaining).to eq('other-owner')
    end

    it 'serializes concurrent callers per user' do
      first_started = false
      second_started = false
      contention_observed = false

      first = Thread.new do
        described_class.with_user_lock(user_id, timeout: 5) do
          first_started = true
          sleep 0.2
          contention_observed = second_started == false
        end
      end

      Thread.pass until first_started

      second = Thread.new do
        described_class.with_user_lock(user_id, timeout: 5) do
          second_started = true
        end
      end

      [first, second].each(&:join)

      expect(contention_observed).to be(true)
      expect(second_started).to be(true)
    end

    it 'isolates locks per user_id' do
      acquired_other = false

      described_class.with_user_lock(user_id) do
        described_class.with_user_lock(user_id + 1, timeout: 0.5) do
          acquired_other = true
        end
      end

      expect(acquired_other).to be(true)
    end

    # Reentrancy: needed because FullHistoryRedetectJob holds the per-user lock
    # and then calls SmartDetect, which post-Phase-2 also wraps in PerUserLock.
    # Without reentrancy, the second acquire would block on its own outer lock
    # and time out.
    describe 'heartbeat variant (.with_user_lock_heartbeat)' do
      it 'yields and releases the lock cleanly on success' do
        result = described_class.with_user_lock_heartbeat(user_id, ttl: 1.second, heartbeat: 0.1, max_wall: 5) { :ok }

        expect(result).to eq(:ok)
        expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(0)
      end

      it 'extends the lock TTL while the block is running' do
        # ttl: 1s, heartbeat: 0.1s — the heartbeat refreshes the TTL before it expires.
        # Block runs for 1.5s which is past the original 1s TTL.
        described_class.with_user_lock_heartbeat(user_id, ttl: 1, heartbeat: 0.1, max_wall: 30) do
          sleep 1.5
          # Mid-block: lock should still be alive because heartbeat refreshed it.
          expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(1)
        end
      end

      it 'token-verifies EXPIRE so a leaked heartbeat cannot extend a NEW owner\'s lock' do
        # Acquire then forcibly overwrite the lock value (simulating a different owner).
        described_class.with_user_lock_heartbeat(user_id, ttl: 1, heartbeat: 0.1, max_wall: 30) do
          Sidekiq.redis { |r| r.set(redis_key, 'someone-else', ex: 1) }
          sleep 0.5
          # Heartbeat tried to EXPIRE — but the Lua guard saw the token mismatch
          # and refused. The lock value remains 'someone-else'.
          expect(Sidekiq.redis { |r| r.get(redis_key) }).to eq('someone-else')
        end
      end

      it 'stops extending past max_wall, allowing the short TTL to expire the lock' do
        # max_wall: 0.4s. ttl: 1s. After max_wall, heartbeat stops refreshing and
        # the lock expires on its short TTL during the block.
        described_class.with_user_lock_heartbeat(user_id, ttl: 1, heartbeat: 0.1, max_wall: 0.4) do
          sleep 0.2
          expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(1)
          sleep 1.4
          # Past max_wall — heartbeat stopped — lock expired.
          expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(0)
        end
      end

      it 'releases the lock when the block raises' do
        expect do
          described_class.with_user_lock_heartbeat(user_id, ttl: 1, heartbeat: 0.1, max_wall: 5) { raise 'boom' }
        end.to raise_error('boom')

        expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(0)
      end
    end

    describe 'reentrancy within the same thread' do
      it 'yields immediately on a nested call for the same user without re-acquiring' do
        inner_ran = false

        described_class.with_user_lock(user_id, timeout: 5) do
          described_class.with_user_lock(user_id, timeout: 0.1) do
            inner_ran = true
          end
        end

        expect(inner_ran).to be(true)
      end

      it 'preserves the outer token across nested calls (does not overwrite)' do
        outer_token = nil
        inner_token = nil
        still_held_after_inner = nil

        described_class.with_user_lock(user_id) do
          outer_token = Sidekiq.redis { |r| r.get(redis_key) }
          described_class.with_user_lock(user_id) do
            inner_token = Sidekiq.redis { |r| r.get(redis_key) }
          end
          still_held_after_inner = Sidekiq.redis { |r| r.get(redis_key) }
        end

        expect(outer_token).to be_present
        expect(inner_token).to eq(outer_token)
        expect(still_held_after_inner).to eq(outer_token)
        expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(0)
      end

      it 'still acquires fresh when the outer call is for a different user_id' do
        described_class.with_user_lock(user_id) do
          described_class.with_user_lock(user_id + 1, timeout: 0.5) do
            other_token = Sidekiq.redis { |r| r.get("tracks:per_user_lock:#{user_id + 1}") }
            outer_token = Sidekiq.redis { |r| r.get(redis_key) }
            expect(other_token).not_to eq(outer_token)
          end
        end
      end
    end
  end
end
