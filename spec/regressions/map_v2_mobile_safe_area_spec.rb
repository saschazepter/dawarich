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

    it 'uses dynamic viewport height for the map body so the iOS URL bar does not clip content' do
      body_class = response.body.match(/<body[^>]*class=['"]([^'"]+)['"]/)&.[](1)

      expect(body_class).to be_present
      expect(body_class).not_to include('h-screen'),
                                "body class is '#{body_class}' — h-screen (100vh) is the largest viewport " \
                                'on iOS Safari; use h-dvh / h-[100dvh] so dynamic browser chrome does ' \
                                'not overlap content'
      expect(body_class).to match(/h-(?:dvh|\[100dvh\])/),
                            "body class is '#{body_class}' — expected h-dvh or h-[100dvh]"
    end
  end
end
