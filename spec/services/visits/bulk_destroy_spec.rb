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

    context 'when visit_ids is blank' do
      subject(:service) { described_class.new(user, []) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors).to include('No visits selected')
      end
    end

    context 'when visit_ids matches no rows' do
      subject(:service) { described_class.new(user, [-1, -2]) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors).to include('No matching visits found')
      end
    end

    context 'when a destroy raises mid-batch' do
      subject(:service) { described_class.new(user, [visit1.id, visit2.id]) }

      it 'rolls back all destroys (transactional)' do
        allow_any_instance_of(Visit).to receive(:destroy!).and_wrap_original do |original, *args|
          raise ActiveRecord::RecordNotDestroyed if original.receiver.id == visit2.id

          original.call(*args)
        end

        expect { service.call }.to raise_error(ActiveRecord::RecordNotDestroyed)
        expect(Visit.where(id: visit1.id)).to exist
        expect(Visit.where(id: visit2.id)).to exist
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
  end
end
