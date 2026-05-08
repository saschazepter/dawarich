# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260508193900_dedupe_tracks_for_unique_index')

RSpec.describe DedupeTracksForUniqueIndex do
  let(:user) { create(:user) }
  let(:start_at) { Time.zone.parse('2026-04-01 10:00:00') }
  let(:end_at) { Time.zone.parse('2026-04-01 10:30:00') }

  # Drop the unique index inside the example transaction so we can seed
  # legacy-style duplicates. The transaction rollback at the end of the
  # example restores the index automatically.
  before do
    ActiveRecord::Base.connection.execute(
      'DROP INDEX IF EXISTS index_tracks_on_user_start_end_unique'
    )
  end

  def make_track(distance:, attached_points: [])
    track = Track.create!(
      user_id: user.id,
      start_at: start_at,
      end_at: end_at,
      original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
      distance: distance,
      duration: (end_at - start_at).to_i,
      avg_speed: 10
    )
    Point.where(id: attached_points.map(&:id)).update_all(track_id: track.id) if attached_points.any?
    track
  end

  def make_point(timestamp_offset:, lat: 52.5, lon: 13.4)
    create(
      :point,
      user: user,
      timestamp: start_at.to_i + timestamp_offset,
      latitude: lat,
      longitude: lon,
      altitude: 50,
      track_id: nil
    )
  end

  def silence_migration
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original_stdout
  end

  it 'preserves the winner and deletes the losers' do
    p1 = make_point(timestamp_offset: 60)
    p2 = make_point(timestamp_offset: 120)
    p3 = make_point(timestamp_offset: 180)

    winner = make_track(distance: 1000, attached_points: [p1, p2, p3])
    loser_a = make_track(distance: 100)
    loser_b = make_track(distance: 50)

    silence_migration { described_class.new.up }

    expect(Track.where(id: winner.id)).to exist
    expect(Track.where(id: [loser_a.id, loser_b.id])).to be_empty
  end

  it 'reassigns loser points inside the winner window to the winner' do
    winner_point = make_point(timestamp_offset: 60)
    loser_in_window = make_point(timestamp_offset: 120)

    winner = make_track(distance: 1000, attached_points: [winner_point])
    make_track(distance: 100, attached_points: [loser_in_window])

    silence_migration { described_class.new.up }

    expect(loser_in_window.reload.track_id).to eq(winner.id)
    expect(winner_point.reload.track_id).to eq(winner.id)
  end

  it 'orphans loser points outside the winner window for later regeneration' do
    in_window = make_point(timestamp_offset: 60)
    out_of_window = make_point(timestamp_offset: (end_at - start_at).to_i + 600)

    winner = make_track(distance: 1000, attached_points: [in_window])
    make_track(distance: 100, attached_points: [out_of_window])

    silence_migration { described_class.new.up }

    expect(out_of_window.reload.track_id).to be_nil
    expect(in_window.reload.track_id).to eq(winner.id)
  end

  it 'deletes track_segments belonging to losers' do
    winner = make_track(distance: 1000)
    loser = make_track(distance: 100)
    loser_segment = create(:track_segment, track: loser)
    winner_segment = create(:track_segment, track: winner)

    silence_migration { described_class.new.up }

    expect(TrackSegment.where(id: loser_segment.id)).to be_empty
    expect(TrackSegment.where(id: winner_segment.id)).to exist
  end

  it 'picks the track with the most points as winner regardless of distance' do
    p1 = make_point(timestamp_offset: 60)
    p2 = make_point(timestamp_offset: 120)
    p3 = make_point(timestamp_offset: 180)

    most_points = make_track(distance: 100, attached_points: [p1, p2, p3])
    long_distance = make_track(distance: 9999)

    silence_migration { described_class.new.up }

    expect(Track.where(id: most_points.id)).to exist
    expect(Track.where(id: long_distance.id)).to be_empty
  end

  it 'is a no-op when no duplicates exist' do
    make_track(distance: 100)

    expect { silence_migration { described_class.new.up } }.not_to(change { Track.count })
  end

  it 'does not affect tracks belonging to other users' do
    other_user = create(:user)
    other_track = Track.create!(
      user_id: other_user.id,
      start_at: start_at,
      end_at: end_at,
      original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
      distance: 500,
      duration: 1800,
      avg_speed: 10
    )

    make_track(distance: 1000)
    make_track(distance: 100)

    silence_migration { described_class.new.up }

    expect(Track.where(id: other_track.id)).to exist
  end
end
