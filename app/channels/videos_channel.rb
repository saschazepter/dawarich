# frozen_string_literal: true

class VideosChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end
