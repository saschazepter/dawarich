# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Suggest do
  describe '#call' do
    let!(:user) { create(:user) }
    let(:start_at) { Time.zone.local(2020, 1, 1, 0, 0, 0) }
    let(:end_at) { Time.zone.local(2020, 1, 1, 5, 0, 0) }

    let!(:points) { create_visit_points(user, start_at) }

    let(:geocoder_struct) do
      Struct.new(:data) do
        def data
          {
            "features": [
              {
                "geometry": {
                  "coordinates": [
                    37.6175406,
                    55.7559395
                  ],
                  "type": 'Point'
                },
                "type": 'Feature',
                "properties": {
                  "osm_id": 681_354_082,
                  "extent": [
                    37.6175406,
                    55.7559395,
                    37.6177036,
                    55.755847
                  ],
                  "country": 'Russia',
                  "city": 'Moscow',
                  "countrycode": 'RU',
                  "postcode": '103265',
                  "type": 'street',
                  "osm_type": 'W',
                  "osm_key": 'highway',
                  "district": 'Tverskoy',
                  "osm_value": 'pedestrian',
                  "name": 'проезд Воскресенские Ворота',
                  "state": 'Moscow'
                }
              }
            ],
            "type": 'FeatureCollection'
          }
        end
      end
    end

    let(:geocoder_response) do
      [geocoder_struct.new]
    end

    subject { described_class.new(user, start_at:, end_at:).call }

    before do
      allow(Geocoder).to receive(:search).and_return(geocoder_response)
    end

    it 'creates places' do
      expect { subject }.to change(Place, :count).by(1)
    end

    it 'creates visits' do
      expect { subject }.to change(Visit, :count).by(2)
    end

    # Notification + ReverseGeocodingJob fan-out moved out of Visits::Suggest
    # into VisitSuggestingJob (Task 13) — Suggest now just returns
    # { visits:, place_ids: } and the calling job coalesces across day-chunks.
    it 'returns the created visits and their place_ids in a hash' do
      result = subject

      expect(result).to be_a(Hash)
      expect(result[:visits]).to all(be_a(Visit))
      expect(result[:place_ids]).to all(be_a(Integer))
    end

    # The Lite plan window is enforced inside `Visits::SmartDetect` (which is
    # what `Visits::Suggest#call` delegates to). The corresponding regression
    # test lives in spec/services/visits/smart_detect_spec.rb.

    context 'when the underlying detector raises a rescued infrastructure error' do
      # Suggest narrowly rescues Tracks::PerUserLock::AcquisitionTimeout,
      # ActiveRecord::QueryCanceled, ActiveRecord::ConnectionTimeoutError.
      # Other StandardError types propagate so Sidekiq can retry them.
      before do
        allow_any_instance_of(Visits::SmartDetect).to receive(:call)
          .and_raise(Tracks::PerUserLock::AcquisitionTimeout, 'busy')
        allow(ExceptionReporter).to receive(:call)
      end

      it 'creates an error notification whose content does not leak the backtrace' do
        expect { described_class.new(user, start_at:, end_at:).call }
          .to change { user.notifications.where(kind: :error).count }.by(1)

        notification = user.notifications.where(kind: :error).last
        expect(notification.title).to eq('Visit detection failed')
        # Backtrace leakage indicators: file paths from the app or the error's own message.
        expect(notification.content).not_to match(%r{app/services/visits}i)
        expect(notification.content).not_to include('busy')
        expect(notification.content).not_to match(/backtrace/i)
      end

      it 'returns an empty hash so the calling job can keep accumulating' do
        result = described_class.new(user, start_at:, end_at:).call
        expect(result).to eq(visits: [], place_ids: [])
      end

      it 'still reports the exception to Sentry via ExceptionReporter' do
        described_class.new(user, start_at:, end_at:).call

        expect(ExceptionReporter).to have_received(:call) do |reported|
          expect(reported).to be_a(Tracks::PerUserLock::AcquisitionTimeout)
          expect(reported.message).to eq('busy')
        end
      end
    end

    context 'when the underlying detector raises a non-rescued StandardError' do
      it 'propagates so Sidekiq retry handles it' do
        allow_any_instance_of(Visits::SmartDetect).to receive(:call)
          .and_raise(StandardError, 'unexpected')

        expect { described_class.new(user, start_at:, end_at:).call }
          .to raise_error(StandardError, 'unexpected')
      end
    end
  end

  private

  def create_visit_points(user, start_time)
    [
      # first visit
      create(:point, :with_known_location, user:, timestamp: start_time),
      create(:point, :with_known_location, user:, timestamp: start_time + 5.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 10.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 15.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 20.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 25.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 30.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 35.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 40.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 45.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 50.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 55.minutes),
      # end of first visit

      # second visit
      create(:point, :with_known_location, user:, timestamp: start_time + 180.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 185.minutes),
      create(:point, :with_known_location, user:, timestamp: start_time + 190.minutes)
      # end of second visit
    ]
  end

  def clear_enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  def have_job_class(job_class)
    satisfy { |job| job['job_class'] == job_class }
  end

  def have_arguments_starting_with(first_argument)
    satisfy { |job| job['arguments'].first == first_argument }
  end
end
