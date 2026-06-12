# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::StartBackfillPointsToponymsJob, type: :job do
  describe '#perform' do
    it 'enqueues a backfill only for reverse-geocoded points missing the country_name column' do
      target = create(:point).tap do |p|
        p.update_columns(country_name: nil, reverse_geocoded_at: Time.current)
      end
      create(:point, country: 'Germany').tap { |p| p.update_columns(reverse_geocoded_at: Time.current) }
      create(:point).tap { |p| p.update_columns(country_name: nil, reverse_geocoded_at: nil) }

      expect { described_class.perform_now }
        .to have_enqueued_job(DataMigrations::BackfillPointsToponymsJob).with(target.id).once
    end
  end
end
