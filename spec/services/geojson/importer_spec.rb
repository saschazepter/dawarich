# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Geojson::Importer do
  describe '#call' do
    subject(:call_service) { service.call }

    let(:user) { create(:user) }
    let(:file_path) { Rails.root.join('spec/fixtures/files/geojson/export.json') }
    let(:import) { create(:import, user:, name: 'geojson.json', source: :geojson) }
    let(:service) { described_class.new(import, user.id, file_path.to_s) }

    it 'creates new points from a FeatureCollection' do
      expect { call_service }.to change { Point.count }.by(10)
    end

    it 'does not load the complete JSON document into memory' do
      allow(service).to receive(:load_json_data).and_raise('full document load attempted')

      expect { call_service }.to change { Point.count }.by(10)
    end

    it 'flushes points in bounded batches' do
      stub_const('Geojson::Importer::BATCH_SIZE', 3)
      allow(service).to receive(:bulk_insert_points).and_call_original

      call_service

      expect(service).to have_received(:bulk_insert_points).exactly(4).times
    end

    it 'does not insert partial data when the JSON document is truncated' do
      malformed = <<~JSON
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [13.4, 52.5] },
              "properties": { "timestamp": 1609459201 }
            }
      JSON

      Tempfile.create(['truncated', '.geojson']) do |file|
        file.write(malformed)
        file.flush
        malformed_service = described_class.new(import, user.id, file.path)
        original_count = Point.count

        expect { malformed_service.call }.to raise_error(Oj::ParseError)
        expect(Point.count).to eq(original_count)
      end
    end

    it 'scrubs invalid UTF-8 without loading the full document' do
      invalid_utf8 = <<~JSON.b.sub('INVALID', "invalid \xFF")
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [13.4, 52.5] },
              "properties": { "timestamp": 1609459201, "label": "INVALID" }
            }
          ]
        }
      JSON

      Tempfile.create(['invalid-utf8', '.geojson'], binmode: true) do |file|
        file.write(invalid_utf8)
        file.flush
        invalid_utf8_service = described_class.new(import, user.id, file.path)

        expect { invalid_utf8_service.call }.to change { Point.count }.by(1)
      end
    end
  end
end
