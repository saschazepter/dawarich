# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::BulkCheckJob do
  include ActiveJob::TestHelper

  it 'enqueues a check for active and trial users only' do
    active = create(:user, status: :active)
    trial = create(:user, status: :trial)
    create(:user, status: :inactive)

    expect { described_class.perform_now }
      .to have_enqueued_job(Achievements::CheckJob).with(active.id, notify: true).once
      .and have_enqueued_job(Achievements::CheckJob).with(trial.id, notify: true).once
  end

  it 'staggers batches and can suppress notifications for backfills' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    users = create_list(:user, 2, status: :active)

    described_class.perform_now(notify: false)

    expect(Achievements::CheckJob).to have_been_enqueued.with(users.first.id, notify: false)
    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == Achievements::CheckJob }
    waits = enqueued.map { |j| j[:at] }.compact
    expect(waits.uniq.size).to be > 1
  end
end
