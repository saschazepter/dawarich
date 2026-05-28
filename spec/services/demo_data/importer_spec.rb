# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DemoData::Importer do
  let(:user) { create(:user) }

  describe '#call' do
    it 'returns :created and creates a demo Import' do
      result = described_class.new(user).call
      expect(result[:status]).to eq(:created)
      expect(user.imports.where(demo: true).count).to eq(1)
    end

    it 'seeds points, tags, places, visits, and a trip in one call' do
      described_class.new(user).call
      expect(user.points.count).to be > 600
      expect(user.tags.demo.count).to be >= 6
      expect(user.visits.demo.count).to be >= 50
      expect(user.trips.demo.count).to eq(1)
    end

    it 'completes synchronously without enqueuing Import::ProcessJob' do
      expect { described_class.new(user).call }.not_to(
        have_enqueued_job(Import::ProcessJob)
      )
    end

    it 'is idempotent — second call returns :exists and does not duplicate data' do
      described_class.new(user).call
      result = described_class.new(user).call
      expect(result[:status]).to eq(:exists)
      expect(user.imports.where(demo: true).count).to eq(1)
    end

    it 'rolls back the entire transaction on seeder error' do
      allow_any_instance_of(DemoData::DerivativesSeeder).to receive(:call).and_raise(StandardError, 'boom')
      result = described_class.new(user).call
      expect(result[:status]).to eq(:error)
      expect(user.imports.where(demo: true).count).to eq(0)
      expect(user.points.count).to eq(0)
    end
  end
end
