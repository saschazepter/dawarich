# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::LiveBroadcaster do
  let(:user) { create(:user) }

  let(:upserted_results) do
    [
      { 'id' => 1, 'timestamp' => 1_700_000_000, 'latitude' => 52.52, 'longitude' => 13.405 }
    ]
  end

  let(:payloads) do
    [
      { timestamp: 1_700_000_000, battery: 85, altitude: 100, velocity: '5.0' }
    ]
  end

  describe '#call' do
    context 'when live_map_enabled is true' do
      before do
        user.settings['live_map_enabled'] = true
        user.save!
      end

      it 'broadcasts point data to PointsChannel' do
        expect(PointsChannel).to receive(:broadcast_to).with(
          user,
          [52.52, 13.405, '85', '100', '1700000000', '5.0', '1', '']
        )

        described_class.new(user.id, upserted_results, payloads).call
      end
    end

    context 'when live_map_enabled is false' do
      before do
        user.settings['live_map_enabled'] = false
        user.save!
      end

      it 'does not broadcast to PointsChannel' do
        expect(PointsChannel).not_to receive(:broadcast_to)

        described_class.new(user.id, upserted_results, payloads).call
      end
    end

    context 'when upserted_results is empty' do
      it 'does not broadcast' do
        expect(PointsChannel).not_to receive(:broadcast_to)
        expect(FamilyLocationsChannel).not_to receive(:broadcast_to)

        described_class.new(user.id, [], payloads).call
      end
    end

    context 'when user does not exist' do
      it 'does not broadcast' do
        expect(PointsChannel).not_to receive(:broadcast_to)
        expect(FamilyLocationsChannel).not_to receive(:broadcast_to)

        described_class.new(-1, upserted_results, payloads).call
      end
    end

    context 'with multiple points' do
      let(:upserted_results) do
        [
          { 'id' => 1, 'timestamp' => 1_700_000_000, 'latitude' => 52.52, 'longitude' => 13.405 },
          { 'id' => 2, 'timestamp' => 1_700_000_060, 'latitude' => 52.53, 'longitude' => 13.41 }
        ]
      end

      let(:payloads) do
        [
          { timestamp: 1_700_000_000, battery: 85, altitude: 100, velocity: '5.0' },
          { timestamp: 1_700_000_060, battery: 80, altitude: 110, velocity: '10.0' }
        ]
      end

      before do
        user.settings['live_map_enabled'] = true
        user.save!
      end

      it 'broadcasts each point' do
        expect(PointsChannel).to receive(:broadcast_to).twice

        described_class.new(user.id, upserted_results, payloads).call
      end
    end

    context 'when payload has no matching timestamp' do
      before do
        user.settings['live_map_enabled'] = true
        user.save!
      end

      let(:payloads) { [{ timestamp: 9_999_999_999, battery: 50, altitude: 0, velocity: '0' }] }

      it 'broadcasts with empty strings for missing fields' do
        expect(PointsChannel).to receive(:broadcast_to).with(
          user,
          [52.52, 13.405, '', '', '1700000000', '', '1', '']
        )

        described_class.new(user.id, upserted_results, payloads).call
      end
    end

    context 'family location broadcast' do
      let(:family) { create(:family) }
      let(:user) { family.creator }

      before do
        allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
        create(:family_membership, family: family, user: user, role: :owner)
        user.update_family_location_sharing!(true, duration: 'permanent')
      end

      context 'when family sharing is enabled' do
        it 'broadcasts to FamilyLocationsChannel with the user payload' do
          expect(FamilyLocationsChannel).to receive(:broadcast_to).with(
            family,
            hash_including(
              user_id: user.id,
              email: user.email,
              email_initial: user.email.first.upcase,
              latitude: 52.52,
              longitude: 13.405,
              timestamp: 1_700_000_000
            )
          )

          described_class.new(user.id, upserted_results, payloads).call
        end

        it 'broadcasts even when live_map_enabled is false' do
          user.settings['live_map_enabled'] = false
          user.save!

          expect(PointsChannel).not_to receive(:broadcast_to)
          expect(FamilyLocationsChannel).to receive(:broadcast_to)

          described_class.new(user.id, upserted_results, payloads).call
        end

        it 'broadcasts to both channels when live_map_enabled and family sharing are both on' do
          user.settings['live_map_enabled'] = true
          user.save!

          expect(PointsChannel).to receive(:broadcast_to)
          expect(FamilyLocationsChannel).to receive(:broadcast_to)

          described_class.new(user.id, upserted_results, payloads).call
        end

        it 'emits one family broadcast per upserted point' do
          multi_results = [
            { 'id' => 1, 'timestamp' => 1_700_000_000, 'latitude' => 52.52, 'longitude' => 13.405 },
            { 'id' => 2, 'timestamp' => 1_700_000_060, 'latitude' => 52.53, 'longitude' => 13.41 }
          ]
          multi_payloads = [
            { timestamp: 1_700_000_000, battery: 85, altitude: 100, velocity: '5.0' },
            { timestamp: 1_700_000_060, battery: 80, altitude: 110, velocity: '10.0' }
          ]

          expect(FamilyLocationsChannel).to receive(:broadcast_to).twice

          described_class.new(user.id, multi_results, multi_payloads).call
        end
      end

      context 'when family sharing is disabled' do
        before { user.update_family_location_sharing!(false) }

        it 'does not broadcast to FamilyLocationsChannel' do
          expect(FamilyLocationsChannel).not_to receive(:broadcast_to)

          described_class.new(user.id, upserted_results, payloads).call
        end
      end

      context 'when family feature is disabled globally' do
        before { allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false) }

        it 'does not broadcast to FamilyLocationsChannel even when user sharing is enabled' do
          expect(FamilyLocationsChannel).not_to receive(:broadcast_to)

          described_class.new(user.id, upserted_results, payloads).call
        end
      end
    end

    context 'when user is not in a family' do
      let(:user) { create(:user) }

      before do
        allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
        user.settings['live_map_enabled'] = false
        user.save!
      end

      it 'does not broadcast to FamilyLocationsChannel' do
        expect(FamilyLocationsChannel).not_to receive(:broadcast_to)

        described_class.new(user.id, upserted_results, payloads).call
      end
    end
  end
end
