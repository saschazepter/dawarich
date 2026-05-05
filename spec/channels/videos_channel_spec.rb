# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideosChannel, type: :channel do
  let(:user) { create(:user) }

  before { stub_connection current_user: user }

  it 'streams for the current user' do
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user)
  end
end
