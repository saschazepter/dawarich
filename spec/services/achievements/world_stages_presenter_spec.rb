# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::WorldStagesPresenter do
  def presenter(country_count)
    codes = %w[DE FR IT ES PT NL BE AT CH PL SE NO DK FI IE GB GR HU RO BG
               CZ SK HR SI EE LV LT LU MT CY US CA MX BR AR CL PE CO EC UY
               ZA KE EG MA NG GH CI TZ UG ZM].first(country_count)
    described_class.new(state: { 'earned' => codes.index_with { '2026-05-01' } })
  end

  describe 'staged rarity' do
    it 'is Common before any milestone' do
      expect(presenter(3).rarity).to eq('Common')
    end

    it 'rises to Rare, Epic, then Legendary across the thresholds' do
      expect(presenter(5).rarity).to eq('Rare')
      expect(presenter(15).rarity).to eq('Epic')
      expect(presenter(50).rarity).to eq('Legendary')
    end
  end

  describe 'stages' do
    it 'exposes three named milestones with reached flags' do
      stages = presenter(15).stages

      expect(stages.map { |s| s[:name] }).to eq(['Border Hopper', 'Globetrotter', 'World Traveler'])
      expect(stages.map { |s| s[:threshold] }).to eq([5, 15, 50])
      expect(stages.map { |s| s[:reached] }).to eq([true, true, false])
    end
  end

  describe 'progress toward the next stage' do
    it 'measures percent against the next unreached threshold' do
      expect(presenter(3).percent).to eq(60)      # 3 of 5
      expect(presenter(10).percent).to eq(67)     # 10 of 15
    end

    it 'labels the count toward the next milestone' do
      expect(presenter(10).earned_label).to eq('10 of 15 countries')
    end

    it 'is complete and Legendary once the final milestone is cleared' do
      set = presenter(50)

      expect(set).to be_completed
      expect(set.percent).to eq(100)
      expect(set.earned_label).to eq('World Traveler')
    end
  end

  describe '#card_attributes' do
    it 'renders one World Explorer card at the current rarity' do
      attrs = presenter(15).card_attributes

      expect(attrs).to include(name: 'World Explorer', rarity: 'Epic', place: 'The World',
                               completed: false, locked: false)
      expect(attrs[:map_zoom]).to be_positive
    end

    it 'is locked with nothing earned' do
      expect(presenter(0)).to be_locked
    end
  end
end
