# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports::Create.monthly_visit_ranges' do
  subject(:ranges) { Imports::Create.monthly_visit_ranges(start_at, end_at) }

  context 'with a range ≤ 32 days' do
    let(:start_at) { Time.zone.local(2026, 3, 1, 0, 0, 0) }
    let(:end_at)   { Time.zone.local(2026, 3, 15, 12, 0, 0) }

    it 'returns a single chunk covering the full range' do
      expect(ranges).to eq([[start_at, end_at]])
    end
  end

  context 'with a multi-month range' do
    let(:start_at) { Time.zone.local(2026, 3, 10, 0, 0, 0) }
    let(:end_at)   { Time.zone.local(2026, 5, 20, 0, 0, 0) }

    it 'splits into one chunk per calendar month' do
      expect(ranges.size).to eq(3)
    end

    it 'first chunk starts at the import start and ends at end of that month' do
      first = ranges.first
      expect(first[0]).to eq(start_at)
      expect(first[1]).to eq(start_at.end_of_month)
    end

    it 'last chunk ends at the import end (clamped to actual end_at)' do
      expect(ranges.last[1]).to eq(end_at)
    end

    it 'chunks are contiguous (no gaps, no overlap)' do
      ranges.each_cons(2) do |a, b|
        expect(b[0]).to be > a[1]
        expect(b[0] - a[1]).to be < 2.seconds
      end
    end
  end

  context 'with a 5-year range (multi-year import path)' do
    let(:start_at) { Time.zone.local(2021, 1, 15, 0, 0, 0) }
    let(:end_at)   { Time.zone.local(2026, 1, 15, 0, 0, 0) }

    it 'fans out into roughly one chunk per month (~60 total)' do
      expect(ranges.size).to be_within(2).of(60)
    end
  end
end
