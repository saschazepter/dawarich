# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GPX track importer tolerates a points table without the altitude_decimal column' do
  let(:user) { create(:user) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx') }
  let(:file) { Rack::Test::UploadedFile.new(file_path, 'application/xml') }
  let(:import) { create(:import, user:, name: 'gpx_track.gpx', source: 'gpx') }

  before do
    import.file.attach(file)
    allow(Point).to receive(:altitude_decimal_supported?).and_return(false)
  end

  it 'imports points without writing altitude_decimal' do
    expect { Gpx::TrackImporter.new(import, user.id).call }.not_to raise_error

    expect(user.points.count).to eq(10)
    expect(user.points.pluck(:altitude_decimal)).to all(be_nil)
  end
end
