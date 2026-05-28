# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLink, type: :model do
  describe 'validations' do
    it 'requires name' do
      link = build(:shared_link, name: nil)
      expect(link).not_to be_valid
      expect(link.errors[:name]).to include("can't be blank")
    end

    it 'requires user' do
      link = build(:shared_link, user: nil)
      expect(link).not_to be_valid
    end

    it 'requires resource_id for trip type' do
      link = build(:shared_link, resource_type: :trip, resource_id: nil, autobuild_trip: false)
      expect(link).not_to be_valid
      expect(link.errors[:resource_id]).to include('is required for this resource type')
    end

    it 'forbids resource_id for live type' do
      link = build(:shared_link, resource_type: :live, resource_id: 42)
      expect(link).not_to be_valid
    end
  end

  describe '#active?' do
    it 'returns true when not revoked and not expired' do
      link = build(:shared_link, revoked_at: nil, expires_at: 1.hour.from_now)
      expect(link).to be_active
    end

    it 'returns false when revoked' do
      link = build(:shared_link, revoked_at: 1.minute.ago)
      expect(link).not_to be_active
    end

    it 'returns false when expired' do
      link = build(:shared_link, expires_at: 1.minute.ago)
      expect(link).not_to be_active
    end

    it 'returns true when no expiry is set' do
      link = build(:shared_link, expires_at: nil, revoked_at: nil)
      expect(link).to be_active
    end
  end

  describe '.active scope' do
    it 'excludes revoked and expired links' do
      active = create(:shared_link)
      create(:shared_link, :revoked)
      create(:shared_link, :expired)
      expect(SharedLink.active).to contain_exactly(active)
    end
  end

  describe '#resource' do
    it 'returns the Trip scoped through user' do
      user = create(:user)
      trip = create(:trip, user: user)
      link = create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id)
      expect(link.resource).to eq(trip)
    end

    it 'never returns another user trip even if resource_id matches' do
      owner = create(:user)
      other_user = create(:user)
      other_trip = create(:trip, user: other_user)
      link = build(:shared_link, user: owner, resource_type: :trip, resource_id: other_trip.id)
      link.save!(validate: false)
      expect(link.resource).to be_nil
    end

    it 'returns the owner user for live shares' do
      link = build(:shared_link, :live)
      expect(link.resource).to eq(link.user)
    end
  end

  describe '#touch_access!' do
    it 'increments view_count and sets last_accessed_at' do
      link = create(:shared_link, view_count: 0, last_accessed_at: nil)
      before_call = Time.current
      link.touch_access!
      link.reload
      expect(link.view_count).to eq(1)
      expect(link.last_accessed_at).to be >= before_call
    end
  end

  describe 'DEFAULT_SETTINGS' do
    it 'provides settings for each resource type' do
      expect(SharedLink::DEFAULT_SETTINGS[:trip]).to include('show_photos' => false, 'show_places' => true)
      expect(SharedLink::DEFAULT_SETTINGS[:track]).to include('show_stats' => true)
      expect(SharedLink::DEFAULT_SETTINGS[:timeline]).to include('show_places' => true)
      expect(SharedLink::DEFAULT_SETTINGS[:live]).to include('history_hours' => 6)
    end

    it 'returns defaults via .default_settings_for' do
      expect(SharedLink.default_settings_for(:trip)).to eq(SharedLink::DEFAULT_SETTINGS[:trip])
      expect(SharedLink.default_settings_for('timeline')).to eq(SharedLink::DEFAULT_SETTINGS[:timeline])
    end
  end
end
