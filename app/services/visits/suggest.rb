# frozen_string_literal: true

class Visits::Suggest
  attr_reader :user, :start_at, :end_at

  def initialize(user, start_at:, end_at:)
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @user = user
  end

  def call
    visits = Visits::SmartDetect.new(user, start_at:, end_at:).call
    return visits if visits.empty?

    create_visits_notification(user)
    if DawarichSettings.reverse_geocoding_enabled?
      visits.filter_map(&:place_id).uniq.each do |place_id|
        ReverseGeocodingJob.perform_later('place', place_id)
      end
    end

    visits
  rescue StandardError => e
    # User-visible content stays short. Full trace + error message go to Sentry
    # via ExceptionReporter, not into the notification.
    user.notifications.create!(
      kind: :error,
      title: 'Visit detection failed',
      content: "We couldn't detect visits for the selected range. " \
               'The team has been notified; please retry from Settings → Visits.'
    )

    ExceptionReporter.call(e)
  end

  private

  def create_visits_notification(user)
    content = <<~CONTENT
      New visits have been suggested based on your location data from #{Time.zone.at(start_at)} to #{Time.zone.at(end_at)}. You can review them on the <a href="/map/v2?panel=timeline&date=today&status=suggested" class="link">Timeline</a> page.
    CONTENT

    user.notifications.create!(
      kind: :info,
      title: 'New visits suggested',
      content:
    )
  end
end
