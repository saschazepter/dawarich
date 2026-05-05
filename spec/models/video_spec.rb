# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Video, type: :model do
  let(:user) { create(:user) }
  let(:track) { create(:track, user:) }

  describe 'associations and validations' do
    it 'belongs to user' do
      video = build(:video, user: nil)
      expect(video).not_to be_valid
    end

    it 'allows a nil track' do
      video = build(:video, user:, track: nil)
      expect(video).to be_valid
    end

    it 'requires start_at and end_at' do
      video = build(:video, user:, start_at: nil, end_at: nil)
      expect(video).not_to be_valid
      expect(video.errors[:start_at]).to be_present
      expect(video.errors[:end_at]).to be_present
    end

    it 'requires end_at to be after start_at' do
      video = build(:video, user:, start_at: 2.days.ago, end_at: 3.days.ago)
      expect(video).not_to be_valid
      expect(video.errors[:end_at]).to include('must be after start date')
    end

    it 'rejects a track that does not belong to the user' do
      other_track = create(:track, user: create(:user))
      video = build(:video, user:, track: other_track)
      expect(video).not_to be_valid
      expect(video.errors[:track_id]).to include('does not belong to this user')
    end
  end

  describe 'callback nonce' do
    it 'generates a urlsafe nonce on create' do
      video = create(:video, user:, track:)
      expect(video.callback_nonce).to be_present
      expect(video.callback_nonce.length).to be >= 32
    end

    it 'does not regenerate the nonce on update' do
      video = create(:video, user:, track:)
      original = video.callback_nonce
      video.update!(status: :processing)
      expect(video.reload.callback_nonce).to eq(original)
    end
  end

  describe 'status enum' do
    it 'defaults to created' do
      video = create(:video, user:, track:)
      expect(video.status).to eq('created')
    end

    it 'has the expected states' do
      expect(Video.statuses.keys).to eq(%w[created processing completed failed])
    end
  end

  describe 'job enqueueing' do
    it 'enqueues VideoJob on create' do
      expect { create(:video, user:, track:) }.to have_enqueued_job(VideoJob)
    end
  end

  describe '#display_name' do
    it 'returns the date range when no track name' do
      video = create(:video, user:, track: nil,
                             start_at: Time.zone.parse('2026-04-01 10:00'),
                             end_at: Time.zone.parse('2026-04-01 18:00'))
      expect(video.display_name).to eq('2026-04-01 — 2026-04-01')
    end
  end

  describe '#download_filename' do
    it 'parameterizes the date range when no track' do
      video = create(:video, user:, track: nil,
                             start_at: Time.zone.parse('2026-04-01 10:00'))
      expect(video.download_filename).to end_with('.mp4')
    end
  end

  describe 'processing_started_at' do
    it 'is set when status moves to processing' do
      video = create(:video, user:, track:)
      expect { video.update!(status: :processing) }
        .to change { video.reload.processing_started_at }.from(nil)
    end
  end

  describe 'broadcast on status change' do
    let(:video) { create(:video, user:, track:) }

    it 'broadcasts on status change' do
      expect do
        video.update!(status: :processing)
      end.to have_broadcasted_to(user).from_channel(VideosChannel)
    end
  end
end
