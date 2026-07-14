# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::CheckJob do
  let(:user) { create(:user) }

  it 'runs the checker for the user' do
    checker = instance_double(Achievements::RegionSetChecker, call: nil)
    allow(Achievements::RegionSetChecker).to receive(:new)
      .with(user, notify: false, oldest_timestamp: nil).and_return(checker)

    described_class.perform_now(user.id, notify: false)

    expect(checker).to have_received(:call)
  end

  it 'forwards the oldest timestamp to the checker' do
    checker = instance_double(Achievements::RegionSetChecker, call: nil)
    allow(Achievements::RegionSetChecker).to receive(:new)
      .with(user, notify: true, oldest_timestamp: 123).and_return(checker)

    described_class.perform_now(user.id, oldest_timestamp: 123)

    expect(checker).to have_received(:call)
  end

  it 'does nothing for a missing user' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
