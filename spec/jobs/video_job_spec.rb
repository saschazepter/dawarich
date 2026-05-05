# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoJob, type: :job do
  let(:user) { create(:user) }
  let(:track) { create(:track, user:) }
  let(:video) { create(:video, user:, track:) }

  before { ActiveJob::Base.queue_adapter = :test }

  it 'is on the videos queue' do
    expect(described_class.new.queue_name).to eq('videos')
  end

  it 'sets the video to processing and calls RequestRender' do
    fake_service = instance_double(Videos::RequestRender, call: true)
    allow(Videos::RequestRender).to receive(:new).with(video:).and_return(fake_service)

    described_class.perform_now(video.id)

    expect(video.reload.status).to eq('processing')
    expect(fake_service).to have_received(:call)
  end

  it 'silently ignores a missing video id' do
    expect { described_class.perform_now(999_999) }.not_to raise_error
  end

  it 'marks failed and reports when RequestRender raises' do
    allow(Videos::RequestRender).to receive(:new)
      .and_raise(Videos::RequestRender::RenderError, 'boom')
    allow(ExceptionReporter).to receive(:call)

    described_class.perform_now(video.id)

    expect(video.reload.status).to eq('failed')
    expect(video.error_message).to eq('boom')
    expect(ExceptionReporter).to have_received(:call)
  end
end
