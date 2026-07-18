# frozen_string_literal: true

class Lite::ArchivalWarningJob < ApplicationJob
  queue_as :archival

  # Thresholds checked daily for all Lite users.
  # Each threshold defines the cutoff duration, a dedup key, and the minimum
  # time the user must have been on Lite (so a fresh downgrade with old data
  # walks through the warning sequence instead of jumping to "archived").
  THRESHOLDS = [
    { duration: DawarichSettings::LITE_DATA_WINDOW - 1.month,            key: '11mo',   action: :notify_approaching,
      min_lite_age: 0.days },
    { duration: DawarichSettings::LITE_DATA_WINDOW - 1.month + 15.days,  key: '11_5mo', action: :notify_email,
      min_lite_age: 15.days },
    { duration: DawarichSettings::LITE_DATA_WINDOW,                      key: '12mo',   action: :notify_archived,
      min_lite_age: 1.month }
  ].freeze

  def perform
    return if DawarichSettings.self_hosted?

    User.where(plan: :lite).find_each do |user|
      next if user.full_access?

      check_thresholds(user)
    end
  end

  private

  def check_thresholds(user)
    warnings_sent = user.settings&.dig('archival_warnings') || {}
    oldest_timestamp = user.points.minimum(:timestamp)
    return unless oldest_timestamp

    lite_since = parse_lite_since(user)

    # Find all crossed thresholds that haven't been sent yet
    unsent_crossed = THRESHOLDS.select do |threshold|
      cutoff = threshold[:duration].ago.to_i
      oldest_timestamp <= cutoff &&
        warnings_sent[threshold[:key]].blank? &&
        lite_long_enough?(lite_since, threshold[:min_lite_age])
    end

    return if unsent_crossed.empty?

    # Only send the most severe (last in the ordered list), mark all as sent
    most_severe = unsent_crossed.last
    send(most_severe[:action], user)
    unsent_crossed.each { |threshold| mark_warning_sent(user, threshold[:key]) }
  end

  def notify_approaching(user)
    Notification.create!(
      user: user,
      kind: :warning,
      title: 'Your oldest data will archive in 30 days',
      content: 'Your oldest month of location data will be archived soon. ' \
               'Upgrade to Pro to keep your full history searchable.'
    )
  end

  def notify_email(user)
    Users::MailerSendingJob.perform_later(user.id, 'archival_approaching')
  end

  def notify_archived(user)
    Notification.create!(
      user: user,
      kind: :warning,
      title: 'Data has been archived',
      content: '1 month of location data has been archived. ' \
               'Your archived data can be exported at any time. ' \
               'Upgrade to Pro to make it visible and interactive in-app again.'
    )
  end

  def parse_lite_since(user)
    raw = user.settings&.dig('lite_since')
    return nil if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue ArgumentError
    nil
  end

  def lite_long_enough?(lite_since, min_lite_age)
    return true if lite_since.nil?

    lite_since <= min_lite_age.ago
  end

  def mark_warning_sent(user, key)
    # Atomic JSONB merge at the SQL level to avoid read-modify-write race conditions
    # when multiple job workers process the same user concurrently.
    User.where(id: user.id).update_all(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "settings = COALESCE(settings, '{}'::jsonb) || " \
          "jsonb_build_object('archival_warnings', " \
          "COALESCE(settings->'archival_warnings', '{}'::jsonb) || " \
          'jsonb_build_object(?, ?))',
          key, Time.zone.now.iso8601
        ]
      )
    )
  end
end
