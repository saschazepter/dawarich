# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visit, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:area).optional }
    it { is_expected.to belong_to(:place).optional }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:points).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:started_at) }
    it { is_expected.to validate_presence_of(:ended_at) }
    it { is_expected.to validate_presence_of(:duration) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates ended_at is greater than started_at' do
      visit = build(:visit, started_at: Time.zone.now, ended_at: Time.zone.now - 1.hour)

      expect(visit).not_to be_valid
      expect(visit.errors[:ended_at]).to include("must be greater than #{visit.started_at}")
    end
  end

  describe 'factory' do
    it { expect(build(:visit)).to be_valid }
  end

  describe 'self-cleanup callbacks' do
    include ActiveJob::TestHelper

    let(:user)      { create(:user) }
    let(:old_place) { create(:place, user: user, source: :photon) }
    let(:new_place) { create(:place, user: user, source: :photon) }
    let!(:visit)    { create(:visit, user: user, place: old_place, area: nil) }

    describe 'after_commit on: :update' do
      it 'enqueues orphan-check for the previous place when place_id changes' do
        expect { visit.update!(place: new_place) }
          .to have_enqueued_job(Places::DeleteIfOrphanJob).with(old_place.id)
      end

      it 'deletes the previous place after the job runs when it is orphan' do
        perform_enqueued_jobs { visit.update!(place: new_place) }

        expect(Place.exists?(old_place.id)).to be false
      end

      it 'does not enqueue when an unrelated attribute changes' do
        expect { visit.update!(name: 'Renamed') }
          .not_to have_enqueued_job(Places::DeleteIfOrphanJob)
      end

      it 'keeps the old place when it is still referenced by another visit' do
        create(:visit, user: user, place: old_place, area: nil)

        perform_enqueued_jobs { visit.update!(place: new_place) }

        expect(Place.exists?(old_place.id)).to be true
      end
    end

    describe 'after_destroy_commit' do
      it 'enqueues orphan-check for the destroyed visit place' do
        expect { visit.destroy! }
          .to have_enqueued_job(Places::DeleteIfOrphanJob).with(old_place.id)
      end

      it 'deletes the place after the job runs when it is orphan' do
        perform_enqueued_jobs { visit.destroy! }

        expect(Place.exists?(old_place.id)).to be false
      end

      it 'is a no-op when visit had no place' do
        orphan_visit = create(:visit, user: user, place: nil, area: nil)

        expect { orphan_visit.destroy! }.not_to raise_error
      end
    end
  end
end
