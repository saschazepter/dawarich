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
end
