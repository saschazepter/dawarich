# frozen_string_literal: true

require 'rails_helper'

# Execution verification: the navbar version-indicator renders the correct
# state for each changelog_consent value on a real authenticated HTML page.
RSpec.describe 'Navbar changelog indicator', type: :request do
  let(:user) { create(:user, admin: true) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in user
  end

  context 'when consent is pending (nil)' do
    it 'shows the opt-in prompt and no chibichange script' do
      get '/settings/users'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Stay up to date?')
      expect(response.body).not_to include('/w/v1/loader.js')
    end
  end

  context 'when consent is granted' do
    it 'renders the chibichange widget script and no prompt' do
      user.update!(changelog_consent: :granted)

      get '/settings/users'

      expect(response.body).to include('/w/v1/loader.js')
      expect(response.body).to include('data-consent="granted"')
      expect(response.body).not_to include('Stay up to date?')
    end
  end

  context 'when consent is declined' do
    it 'shows neither the prompt nor the script' do
      user.update!(changelog_consent: :declined)

      get '/settings/users'

      expect(response.body).not_to include('Stay up to date?')
      expect(response.body).not_to include('/w/v1/loader.js')
    end
  end
end
