# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::PrivacyZoneMasker do
  let(:user) { create(:user) }

  def make_zone(lat:, lon:, radius: 1000)
    tag = create(:tag, :privacy_zone, user: user, privacy_radius_meters: radius)
    place = create(:place, user: user, latitude: lat, longitude: lon)
    create(:tagging, tag: tag, taggable: place)
    tag
  end

  describe '#any?' do
    it 'is false when the user has no privacy zones' do
      expect(described_class.new(user).any?).to be(false)
    end

    it 'is true when the user has a privacy zone with a place' do
      make_zone(lat: 52.444, lon: 13.500)

      expect(described_class.new(user).any?).to be(true)
    end
  end

  describe '#mask_points' do
    it 'returns the relation untouched when there are no zones' do
      inside = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')

      result = described_class.new(user).mask_points(user.points)

      expect(result).to include(inside)
    end

    it 'excludes points inside a zone and keeps points outside' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      inside = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
      outside = create(:point, user: user, lonlat: 'POINT(13.700 52.600)')

      result = described_class.new(user).mask_points(user.points)

      expect(result).to include(outside)
      expect(result).not_to include(inside)
    end

    it 'excludes a point inside any of several zones' do
      make_zone(lat: 52.444, lon: 13.500, radius: 1000)
      make_zone(lat: 48.137, lon: 11.575, radius: 1000)
      berlin = create(:point, user: user, lonlat: 'POINT(13.500 52.444)')
      munich = create(:point, user: user, lonlat: 'POINT(11.575 48.137)')
      elsewhere = create(:point, user: user, lonlat: 'POINT(2.349 48.853)')

      result = described_class.new(user).mask_points(user.points)

      expect(result).to contain_exactly(elsewhere)
      expect(result).not_to include(berlin, munich)
    end
  end
end
