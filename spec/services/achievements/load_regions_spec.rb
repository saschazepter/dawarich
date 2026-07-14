# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::LoadRegions do
  describe '#call' do
    before { described_class.new.call }

    it 'seeds exactly the regions the registry references' do
      expected = Achievements::Registry.region_sets.flat_map(&:region_codes).sort

      expect(Region.pluck(:code).sort).to eq(expected)
    end

    it 'stores valid geometries' do
      expect(Region.where('NOT ST_IsValid(geom)').count).to eq(0)
    end

    it 'is idempotent' do
      expect { described_class.new.call }.not_to change(Region, :count)
    end
  end
end
