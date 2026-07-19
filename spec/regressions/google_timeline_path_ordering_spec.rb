# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Google Timeline path ordering' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, name: 'Timeline.json') }
  let(:timestamp) { Time.iso8601('2026-06-15T10:35:00Z').to_i }
  let(:timeline) do
    {
      'semanticSegments' => [
        {
          'startTime' => '2026-06-15T10:30:00Z',
          'endTime' => '2026-06-15T10:40:00Z',
          'timelinePath' => [
            { 'point' => '48.1000°, 11.5000°', 'time' => '2026-06-15T10:35:00Z' },
            { 'point' => '48.2000°, 11.6000°', 'time' => '2026-06-15T10:35:00Z' },
            { 'point' => '48.3000°, 11.7000°', 'time' => '2026-06-15T10:35:00Z' }
          ]
        }
      ]
    }
  end

  it 'preserves source order when path points share a minute-resolution timestamp' do
    file = Tempfile.new(['timeline', '.json'])
    file.write(timeline.to_json)
    file.close

    GoogleMaps::PhoneTakeoutImporter.new(import, user.id, file.path).call

    points = user.points.order(:timestamp)
    expect(points.pluck(:timestamp)).to eq([timestamp, timestamp + 1, timestamp + 2])
    expect(points.map { |point| [point.lat, point.lon] }).to eq(
      [[48.1, 11.5], [48.2, 11.6], [48.3, 11.7]]
    )
  ensure
    file&.unlink
  end
end
