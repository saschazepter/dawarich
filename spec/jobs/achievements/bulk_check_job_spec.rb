# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::BulkCheckJob do
  include ActiveJob::TestHelper

  it 'enqueues a check for active and trial users only' do
    active = create(:user, status: :active)
    trial = create(:user, status: :trial)
    create(:user, status: :inactive)

    expect { described_class.perform_now }
      .to have_enqueued_job(Achievements::CheckJob).with(active.id).once
      .and have_enqueued_job(Achievements::CheckJob).with(trial.id).once
  end
end
