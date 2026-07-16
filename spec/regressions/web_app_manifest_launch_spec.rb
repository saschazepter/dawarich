# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Web app manifest launch behavior' do
  subject(:manifest) do
    JSON.parse(Rails.root.join('public/site.webmanifest').read)
  end

  it 'opens the Map v2 application within the site scope' do
    expect(manifest).to include(
      'start_url' => '/map/v2',
      'scope' => '/'
    )
  end

  it 'declares the fields browsers require for installation' do
    expect(manifest).to include(
      'name' => 'Dawarich',
      'short_name' => 'Dawarich',
      'display' => 'standalone'
    )
    expect(manifest['icons']).to include(
      hash_including('sizes' => '192x192'),
      hash_including('sizes' => '512x512'),
      hash_including('purpose' => 'maskable')
    )
  end
end

RSpec.describe 'PWA installability', type: :request do
  shared_examples 'a page with PWA meta tags' do
    it 'links the web app manifest, apple touch icon and theme color' do
      expect(response.body).to include('rel="manifest"')
      expect(response.body).to include('href="/site.webmanifest"')
      expect(response.body).to include('name="theme-color"')
      expect(response.body).to include('rel="apple-touch-icon"')
      expect(response.body).to include('name="mobile-web-app-capable"')
    end
  end

  describe 'application layout' do
    before { get new_user_session_path }

    it_behaves_like 'a page with PWA meta tags'
  end

  describe 'map layout (the manifest start_url)' do
    before do
      sign_in create(:user)
      get map_v2_path
    end

    it_behaves_like 'a page with PWA meta tags'
  end
end
