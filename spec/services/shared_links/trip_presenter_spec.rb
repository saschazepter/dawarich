# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedLinks::TripPresenter do
  let(:user) { create(:user) }
  let(:trip) { create(:trip, user: user, description: '') }
  let(:settings) { {} }
  let(:link) do
    create(:shared_link, user: user, resource_type: :trip, resource_id: trip.id, settings: settings)
  end

  subject(:presenter) { described_class.new(link, trip) }

  describe '#wrapper_data' do
    context 'when the route is shown (map enabled)' do
      let(:settings) { { 'show_route' => true } }

      it 'returns the stimulus controller wiring' do
        data = presenter.wrapper_data
        expect(data[:controller]).to eq('shared-trip-map')
        expect(data[:'shared-trip-map-link-id-value']).to eq(link.id)
        expect(data[:'shared-trip-map-timezone-value']).to eq(user.timezone_iana)
      end
    end

    context 'when the route is hidden' do
      let(:settings) { { 'show_route' => false } }

      it 'returns an empty hash' do
        expect(presenter.wrapper_data).to eq({})
      end
    end
  end

  describe '#interactive_class and #row_data' do
    context 'with the map enabled' do
      let(:settings) { { 'show_route' => true } }

      it 'adds hover styling and the day action wiring' do
        expect(presenter.interactive_class).to include('cursor-pointer')
        expect(presenter.row_data('2026-04-01')).to include(day_key: '2026-04-01', action: described_class::ROW_ACTIONS)
      end
    end

    context 'without the map' do
      let(:settings) { { 'show_route' => false } }

      it 'is non-interactive' do
        expect(presenter.interactive_class).to eq('')
        expect(presenter.row_data('2026-04-01')).to eq({})
      end
    end
  end

  describe '#description?' do
    it 'is false when there is no description body' do
      expect(presenter.description?).to be(false)
    end

    it 'is true when description is shown and present' do
      trip.description = 'A lovely trip'
      trip.save!
      expect(described_class.new(link, trip).description?).to be(true)
    end
  end

  describe '#notes' do
    it 'is empty when day notes are disabled' do
      expect(presenter.notes).to eq({})
    end
  end
end
