# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPointsToponymsJob, type: :job do
  describe '#perform' do
    context 'when geodata still holds the toponyms' do
      let(:point) do
        create(:point, country: 'Germany').tap do |p|
          p.update_columns(
            country_name: nil,
            city: nil,
            country_id: nil,
            geodata: { 'properties' => { 'country' => 'Germany', 'city' => 'Berlin' } },
            reverse_geocoded_at: Time.current
          )
        end
      end

      it 'fills the columns from geodata without re-geocoding' do
        expect { described_class.perform_now(point.id) }
          .not_to have_enqueued_job(ReverseGeocodingJob)

        point.reload
        expect(point.read_attribute(:country_name)).to eq('Germany')
        expect(point.city).to eq('Berlin')
        expect(point.country_id).to eq(Country.find_by(name: 'Germany').id)
      end
    end

    context 'when geodata is empty' do
      let(:point) do
        create(:point).tap do |p|
          p.update_columns(country_name: nil, city: nil, geodata: {}, reverse_geocoded_at: Time.current)
        end
      end

      it 'enqueues a forced re-geocode to repopulate the columns from coordinates' do
        expect { described_class.perform_now(point.id) }
          .to have_enqueued_job(ReverseGeocodingJob).with('Point', point.id, force: true)
      end
    end

    context 'when the columns are already populated' do
      let(:point) { create(:point, city: 'Berlin', country: 'Germany') }

      it 'does nothing' do
        expect { described_class.perform_now(point.id) }
          .not_to have_enqueued_job(ReverseGeocodingJob)
      end
    end
  end
end
