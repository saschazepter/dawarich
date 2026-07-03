# frozen_string_literal: true

module SharedLinksHelper
  def formatted_date_range(start_date, end_date)
    start_date = Date.parse(start_date.to_s) unless start_date.is_a?(Date)
    end_date   = Date.parse(end_date.to_s)   unless end_date.is_a?(Date)

    if start_date == end_date
      start_date.strftime('%B %-d, %Y')
    elsif start_date.year == end_date.year && start_date.month == end_date.month
      "#{start_date.strftime('%B %-d')}–#{end_date.strftime('%-d, %Y')}"
    elsif start_date.year == end_date.year
      "#{start_date.strftime('%B %-d')} – #{end_date.strftime('%B %-d, %Y')}"
    else
      "#{start_date.strftime('%b %-d, %Y')} – #{end_date.strftime('%b %-d, %Y')}"
    end
  end

  def timeline_share_subtitle(share)
    return nil unless share&.timeline?

    range = formatted_date_range(share.settings['start_date'], share.settings['end_date'])
    "#{range} is shared via a public link."
  end

  def trip_share_subtitle(trip)
    "#{trip.name} is shared via a public link."
  end

  def track_share_label(track, unit)
    mode = track.dominant_mode&.titleize.presence || 'Track'
    zone = track.user.timezone_iana.presence || 'UTC'
    date = track.start_at.in_time_zone(zone).strftime('%-d %b %Y')
    distance = track.distance_in_unit(unit).round
    "#{mode} · #{date} · #{distance} #{unit}"
  end

  PUBLIC_SHARE_CTA_BASE = 'https://dawarich.app'

  def public_share_cta_url(utm_content, path: '/')
    utm = {
      utm_source: 'dawarich_share',
      utm_medium: 'public_share',
      utm_campaign: 'cloud',
      utm_content: utm_content
    }.to_query
    "#{PUBLIC_SHARE_CTA_BASE}#{path}?#{utm}"
  end
end
