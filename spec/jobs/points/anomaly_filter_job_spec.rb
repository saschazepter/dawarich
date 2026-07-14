# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyFilterJob do
  include ActiveJob::TestHelper

  it 'retries transient database deadlocks' do
    filter = instance_double(Points::AnomalyFilter)
    allow(Points::AnomalyFilter).to receive(:new).with(42, 100, 200).and_return(filter)
    allow(filter).to receive(:call).and_raise(ActiveRecord::Deadlocked, 'deadlock detected')

    expect do
      described_class.perform_now(42, 100, 200)
    end.to have_enqueued_job(described_class).with(42, 100, 200)
  end
end
