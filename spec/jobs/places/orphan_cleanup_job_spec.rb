# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::OrphanCleanupJob, type: :job do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  describe '#perform' do
    it 'deletes orphan photon places for the given user only' do
      orphan         = create(:place, user: user,  source: :photon, name: Place::DEFAULT_NAME)
      chosen         = create(:place, user: user,  source: :photon, name: Place::DEFAULT_NAME)
      manual         = create(:place, user: user,  source: :manual)
      noted          = create(:place, user: user,  source: :photon, name: Place::DEFAULT_NAME, note: 'mine')
      tagged         = create(:place, user: user,  source: :photon, name: Place::DEFAULT_NAME)
      named_by_photon = create(:place, user: user, source: :photon, name: 'Café Bravo')
      other_orphan = create(:place, user: other, source: :photon, name: Place::DEFAULT_NAME)

      tag = create(:tag, user: user)
      tagged.tags << tag

      create(:visit, user: user, place: chosen, area: nil)

      described_class.new.perform(user.id)

      expect(Place.exists?(orphan.id)).to be(false)
      expect(Place.exists?(chosen.id)).to be(true)
      expect(Place.exists?(manual.id)).to be(true)
      expect(Place.exists?(noted.id)).to be(true)
      expect(Place.exists?(tagged.id)).to be(true)
      expect(Place.exists?(named_by_photon.id)).to be(true)
      expect(Place.exists?(other_orphan.id)).to be(true)
    end

    it 'is idempotent on second run' do
      orphan = create(:place, user: user, source: :photon, name: Place::DEFAULT_NAME)
      described_class.new.perform(user.id)
      expect { described_class.new.perform(user.id) }.not_to raise_error
      expect(Place.exists?(orphan.id)).to be(false)
    end

    it 'deletes place_visits rows referencing orphan places' do
      manual_place = create(:place, user: user, source: :manual)
      orphan       = create(:place, user: user, source: :photon, name: Place::DEFAULT_NAME)
      visit        = create(:visit, user: user, area: nil, place: manual_place)
      PlaceVisit.create!(place: orphan, visit: visit)

      described_class.new.perform(user.id)

      expect(PlaceVisit.exists?(place_id: orphan.id)).to be(false)
      expect(Place.exists?(orphan.id)).to be(false)
    end

    it 'no-ops for unknown user' do
      expect { described_class.new.perform(0) }.not_to raise_error
    end
  end
end
