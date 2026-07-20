# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Traccar KML LineString timestamps' do
  let(:file_path) { Rails.root.join('spec/fixtures/files/kml/traccar_linestring.kml').to_s }

  def import_for(user)
    create(:import, user:, name: 'traccar.kml', source: 'kml')
  end

  it 'imports points across the named time range' do
    user = create(:user, settings: { 'timezone' => 'Berlin' })
    import = import_for(user)

    expect { Kml::Importer.new(import, user.id, file_path).call }.to change(Point, :count).by(3)

    zone = ActiveSupport::TimeZone['Berlin']
    expected_timestamps = [
      zone.parse('2026-05-23 16:55').to_i,
      zone.parse('2026-05-23 16:56').to_i,
      zone.parse('2026-05-23 16:57').to_i
    ]

    expect(user.points.order(:timestamp).pluck(:timestamp)).to eq(expected_timestamps)
  end

  it 'reads the offset-less track name in the owner timezone, not the server timezone' do
    user = create(:user, settings: { 'timezone' => 'Pacific Time (US & Canada)' })
    import = import_for(user)

    Kml::Importer.new(import, user.id, file_path).call

    zone = ActiveSupport::TimeZone['Pacific Time (US & Canada)']
    expect(user.points.order(:timestamp).first.timestamp).to eq(zone.parse('2026-05-23 16:55').to_i)
  end
end
