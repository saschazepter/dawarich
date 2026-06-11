# frozen_string_literal: true

class SharedLinkContext
  attr_reader :shared_link

  def initialize(shared_link)
    @shared_link = shared_link
  end

  def owner
    shared_link.user
  end

  def settings
    shared_link.settings || {}
  end

  def show_photos?
    settings['show_photos'] == true
  end

  def show_stats?
    settings['show_stats'] != false
  end
end
