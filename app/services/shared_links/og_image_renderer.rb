# frozen_string_literal: true

module SharedLinks
  class OgImageRenderer
    def initialize(shared_link)
      @link = shared_link
    end

    def call
      browser = Ferrum::Browser.new(
        window_size: [1200, 630],
        browser_options: { 'no-sandbox' => nil, 'disable-gpu' => nil }
      )
      browser.headers.add('X-OG-Render-Token' => render_token)
      browser.goto(render_url)
      browser.network.wait_for_idle(timeout: 10)
      browser.screenshot(format: 'png', encoding: :binary, full: false)
    ensure
      browser&.quit
    end

    private

    def render_url
      base = ENV.fetch('OG_RENDER_BASE_URL') do
        "http://#{ENV.fetch('OG_RENDER_INTERNAL_HOST', 'localhost')}:#{ENV.fetch('OG_RENDER_INTERNAL_PORT', 3000)}"
      end
      "#{base}/s/#{@link.id}/og.html"
    end

    def render_token
      ENV.fetch('OG_RENDER_TOKEN') { raise 'OG_RENDER_TOKEN must be set' }
    end
  end
end
