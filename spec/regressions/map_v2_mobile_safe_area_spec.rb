# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map V2 mobile viewport / safe-area handling', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /map/v2' do
    before { get map_v2_path }

    it 'declares viewport-fit=cover so iOS Safari respects safe-area insets' do
      viewport = response.body.match(/<meta name="viewport" content="([^"]+)"/)&.[](1)

      expect(viewport).to be_present
      expect(viewport).to include('viewport-fit=cover'),
                          "viewport meta is '#{viewport}' — without viewport-fit=cover, " \
                          'iOS Safari treats env(safe-area-inset-*) as zero'
    end

    it 'uses dynamic viewport height with an h-screen fallback for older browsers' do
      body_class = response.body.match(/<body[^>]*class=['"]([^'"]+)['"]/)&.[](1)

      expect(body_class).to be_present
      expect(body_class).to match(/h-(?:dvh|\[100dvh\])/),
                            "body class is '#{body_class}' — expected h-dvh or h-[100dvh] " \
                            'so dynamic browser chrome does not overlap content'
      expect(body_class).to include('h-screen'),
                            "body class is '#{body_class}' — keep h-screen alongside h-[100dvh] so " \
                            'browsers without dvh support (Safari <15.4, Chrome <108) still render a sized body'
    end

    it 'pushes the fixed navbar below the iOS notch via env(safe-area-inset-top)' do
      expect(response.body).to include('pt-[env(safe-area-inset-top)]'),
                               'fixed navbar must reserve top padding for the notch when viewport-fit=cover ' \
                               'is active, otherwise the notch overlays navbar content'
    end
  end
end
