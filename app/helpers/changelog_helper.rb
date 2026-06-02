# frozen_string_literal: true

module ChangelogHelper
  def chibichange_widget_src
    "#{CHIBICHANGE_WIDGET_HOST}/w/v1/loader.js"
  end

  # Which navbar version indicator to render:
  #   :widget — chibichange "What's New" pill
  #   :prompt — native badge + opt-in card
  #   :badge  — native GitHub-release badge only
  #
  # On cloud (not self-hosted) there is no third-party phone-home concern —
  # it is our own infrastructure — so signed-in users always see the widget
  # with no prompt. Self-hosted instances respect the per-user consent choice.
  def changelog_indicator_state(user = current_user)
    return :badge if user.nil?
    return :widget unless DawarichSettings.self_hosted?
    return :widget if user.changelog_consent_granted?
    return :prompt if user.changelog_prompt_pending?

    :badge
  end
end
