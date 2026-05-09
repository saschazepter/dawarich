# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::BulkDestroy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let!(:visit1) { create(:visit, user: user) }
  let!(:visit2) { create(:visit, user: user) }
  let!(:visit3) { create(:visit, user: user) }
  let!(:other_user_visit) { create(:visit, user: other_user) }

  describe '#call' do
    context 'when given valid visit ids' do
      let(:visit_ids) { [visit1.id, visit2.id] }
      subject(:service) { described_class.new(user, visit_ids) }

      it 'destroys the specified visits' do
        result = service.call

        expect(result[:count]).to eq(2)
        expect(Visit.where(id: visit_ids)).to be_empty
        expect(Visit.where(id: visit3.id)).to exist
      end

      it 'leaves other users\' visits untouched' do
        service.call

        expect(other_user_visit.reload).to be_persisted
      end

      it 'returns the started_ats of destroyed visits' do
        result = service.call

        expect(result[:started_ats]).to contain_exactly(visit1.started_at, visit2.started_at)
      end
    end

    context 'when an id belongs to another user' do
      let(:visit_ids) { [visit1.id, other_user_visit.id] }
      subject(:service) { described_class.new(user, visit_ids) }

      it 'destroys only the user\'s own visits' do
        result = service.call

        expect(result[:count]).to eq(1)
        expect(Visit.where(id: visit1.id)).to be_empty
        expect(other_user_visit.reload).to be_persisted
      end
    end

    context 'plan-tier scoping' do
      it 'refuses to destroy visits outside the Lite data window' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
        old_visit = create(:visit, user: user, started_at: 13.months.ago, ended_at: 13.months.ago + 30.minutes)

        result = described_class.new(user, [old_visit.id]).call

        expect(result).to be(false)
        expect(old_visit.reload).to be_persisted
      end
    end

    context 'when visit_ids is blank' do
      subject(:service) { described_class.new(user, []) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors).to include('No visits selected')
      end
    end

    context 'when visit_ids exceeds the maximum batch size' do
      subject(:service) { described_class.new(user, (1..(described_class::MAX_VISIT_IDS + 1)).to_a) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors.first).to match(/Too many visits/i)
      end
    end

    context 'when visit_ids matches no rows' do
      subject(:service) { described_class.new(user, [-1, -2]) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors).to include('No matching visits found')
      end
    end

    context 'when the bulk delete raises mid-transaction' do
      subject(:service) { described_class.new(user, [visit1.id, visit2.id]) }

      it 'rolls back the whole batch and reports an error' do
        point = create(:point, user: user, visit: visit1)
        original_where = PlaceVisit.method(:where)
        allow(PlaceVisit).to receive(:where) do |args|
          relation = original_where.call(args)
          if args.is_a?(Hash) && Array(args[:visit_id]).sort == [visit1.id, visit2.id].sort
            allow(relation).to receive(:delete_all).and_raise(ActiveRecord::StatementInvalid)
          end
          relation
        end

        expect(service.call).to be(false)
        expect(service.errors).to include(/database error/i)
        expect(Visit.where(id: [visit1.id, visit2.id]).count).to eq(2)
        expect(point.reload.visit_id).to eq(visit1.id)
      end
    end

    context 'point cascade' do
      let!(:point) { create(:point, user: user, visit: visit1) }
      subject(:service) { described_class.new(user, [visit1.id]) }

      it 'nullifies points\' visit_id (does not delete points)' do
        expect { service.call }.not_to change(Point, :count)
        expect(point.reload.visit_id).to be_nil
      end
    end

    context 'when visit_ids spans more than one chunk' do
      let(:visit_count) { described_class::POINT_NULLIFY_BATCH + 10 }
      let!(:many_visits) { create_list(:visit, visit_count, user: user) }
      let!(:points_with_visits) do
        many_visits.map { |v| create(:point, user: user, visit: v) }
      end
      subject(:service) { described_class.new(user, many_visits.map(&:id)) }

      it 'destroys every visit and nullifies every point across chunks' do
        result = service.call

        expect(result[:count]).to eq(visit_count)
        expect(Visit.where(id: many_visits.map(&:id))).to be_empty
        expect(Point.where(id: points_with_visits.map(&:id)).pluck(:visit_id)).to all(be_nil)
      end
    end

    context 'place_visit cascade' do
      let!(:place) { create(:place) }
      let!(:place_visit) { create(:place_visit, visit: visit1, place: place) }
      subject(:service) { described_class.new(user, [visit1.id]) }

      it 'deletes the visit\'s place_visits' do
        service.call

        expect(PlaceVisit.where(id: place_visit.id)).to be_empty
        expect(Place.where(id: place.id)).to exist
      end
    end
  end
end
