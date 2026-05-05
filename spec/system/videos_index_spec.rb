# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Videos page', type: :system do
  let(:user) { create(:user, :pro_plan) }
  let(:track) { create(:track, user:) }

  before do
    driven_by(:rack_test)
    ENV['VIDEO_SERVICE_URL'] = 'http://x'
    DawarichSettings.instance_variable_set(:@video_service_enabled, nil)
    sign_in user
    create(:point, user:, track:, longitude: 13.4, latitude: 52.5,
                   timestamp: track.start_at.to_i)
    stub_request(:post, %r{/api/render}).to_return(status: 200, body: '{}')
  end

  after do
    ENV.delete('VIDEO_SERVICE_URL')
    DawarichSettings.instance_variable_set(:@video_service_enabled, nil)
  end

  it 'lists no videos initially, then shows a row after creating one' do
    visit videos_path
    expect(page).to have_content('No videos yet')

    Video.create!(user:, track:, start_at: track.start_at, end_at: track.end_at)

    visit videos_path
    expect(page).to have_css('table tbody tr')
  end
end
