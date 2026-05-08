# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::PerUserLock, :non_transactional, threads: 4 do
  let(:user_a) { create(:user) }
  let(:user_b) { create(:user) }

  def in_thread(latch_start, ready_latch = nil)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ready_latch&.count_down
        latch_start.wait
        yield
      end
    end
  end

  describe '.with_user_lock' do
    it 'serializes blocks for the same user across threads' do
      order = Concurrent::Array.new
      start_latch = Concurrent::CountDownLatch.new(1)
      ready_latch = Concurrent::CountDownLatch.new(2)

      t1 = in_thread(start_latch, ready_latch) do
        described_class.with_user_lock(user_a.id) do
          order << :t1_in
          sleep 0.2
          order << :t1_out
        end
      end

      t2 = in_thread(start_latch, ready_latch) do
        described_class.with_user_lock(user_a.id) do
          order << :t2_in
          order << :t2_out
        end
      end

      ready_latch.wait
      start_latch.count_down
      [t1, t2].each(&:join)

      expect(order.to_a).to eq(%i[t1_in t1_out t2_in t2_out])
        .or eq(%i[t2_in t2_out t1_in t1_out])
    end

    it 'allows concurrent execution for different users' do
      events = Concurrent::Array.new
      start_latch = Concurrent::CountDownLatch.new(1)
      ready_latch = Concurrent::CountDownLatch.new(2)
      both_inside = Concurrent::CountDownLatch.new(2)

      t1 = in_thread(start_latch, ready_latch) do
        described_class.with_user_lock(user_a.id) do
          events << :a_in
          both_inside.count_down
          both_inside.wait(2)
          events << :a_out
        end
      end

      t2 = in_thread(start_latch, ready_latch) do
        described_class.with_user_lock(user_b.id) do
          events << :b_in
          both_inside.count_down
          both_inside.wait(2)
          events << :b_out
        end
      end

      ready_latch.wait
      start_latch.count_down
      [t1, t2].each(&:join)

      expect(events).to contain_exactly(:a_in, :b_in, :a_out, :b_out)
      expect(events.first(2)).to contain_exactly(:a_in, :b_in)
    end

    it 'releases the lock when the block raises' do
      expect do
        described_class.with_user_lock(user_a.id) { raise 'boom' }
      end.to raise_error('boom')

      acquired = false
      Timeout.timeout(1) do
        described_class.with_user_lock(user_a.id) { acquired = true }
      end
      expect(acquired).to be true
    end

    it 'returns the value of the block' do
      result = described_class.with_user_lock(user_a.id) { 42 }
      expect(result).to eq(42)
    end
  end
end
