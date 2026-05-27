# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MemorySerializer do
  let(:user) { create(:user) }
  let(:anchor) { Time.zone.local(2026, 5, 21, 12) }

  before do
    create(:point, user: user,
                   timestamp: (anchor - 1.month).to_i,
                   latitude: 52.52, longitude: 13.40,
                   lonlat: 'POINT(13.40 52.52)',
                   city: 'Berlin', country: 'Germany')
    create(:point, user: user,
                   timestamp: (anchor - 1.year).to_i,
                   latitude: 41.90, longitude: 12.50,
                   lonlat: 'POINT(12.50 41.90)',
                   city: 'Rome', country: 'Italy')
  end

  subject(:payload) { described_class.new(user, anchor: anchor).call }

  it 'returns an :anchor key with the lookup date for client-side display' do
    expect(payload[:anchor]).to eq(anchor.to_date.iso8601)
  end

  it 'embeds the memory chapters in chronological-by-distance order' do
    expect(payload[:chapters].length).to eq(2)
    expect(payload[:chapters].first[:name]).to eq('Berlin')
  end

  it 'exposes each chapter with the keys the partial reads' do
    chapter = payload[:chapters].first
    expect(chapter).to include(
      :period_key, :period_label, :period_short,
      :date, :date_long, :date_short,
      :name, :country, :lat, :lon, :bucket, :caption_html
    )
  end
end
