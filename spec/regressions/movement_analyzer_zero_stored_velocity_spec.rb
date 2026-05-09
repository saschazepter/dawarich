# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MovementAnalyzer falls back to displacement when stored velocity is zero' do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  it 'classifies a moving sequence with stored velocity 0 as non-stationary' do
    points = (0..10).map do |i|
      build(:point,
            user: user,
            timestamp: 1000 + (i * 60),
            velocity: '0',
            lonlat: "POINT(#{13.404954 + (i * 0.01)} 52.520008)")
    end

    segments = TransportationModes::MovementAnalyzer.new(track, points).call

    expect(segments).not_to be_empty
    expect(segments.map { |s| s[:avg_speed] }.max).to be > 0
    expect(segments.map { |s| s[:mode] }.any? { |m| m != :stationary }).to be(true)
  end

  it 'still reports zero speed when both stored velocity is 0 and points are co-located' do
    same_lonlat = 'POINT(13.404954 52.520008)'
    points = (0..5).map do |i|
      build(:point,
            user: user,
            timestamp: 1000 + (i * 60),
            velocity: '0',
            lonlat: same_lonlat)
    end

    segments = TransportationModes::MovementAnalyzer.new(track, points).call

    expect(segments.map { |s| s[:avg_speed] }).to all(eq(0))
  end

  it 'still trusts a positive stored velocity over displacement' do
    points = (0..10).map do |i|
      build(:point,
            user: user,
            timestamp: 1000 + (i * 60),
            velocity: '1.4',
            lonlat: "POINT(13.404954 #{52.520008 + (i * 0.0001)})")
    end

    segments = TransportationModes::MovementAnalyzer.new(track, points).call

    expect(segments.first[:mode]).to eq(:walking)
  end
end
