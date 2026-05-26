# frozen_string_literal: true

require 'rails_helper'
require 'fugit'
require 'yaml'

RSpec.describe 'config/schedule.yml cron validity' do
  schedule_path = Rails.root.join('config/schedule.yml')
  schedule = YAML.load_file(schedule_path)

  schedule.each do |job_name, definition|
    it "#{job_name} has a valid cron expression" do
      expr = definition['cron']
      expect(expr).to be_a(String), "missing cron entry for #{job_name}"
      parsed = Fugit::Cron.parse(expr)
      expect(parsed).not_to be_nil,
        "invalid cron expression #{expr.inspect} for #{job_name} — " \
        'cron format is "minute hour day month dow"; common typo: writing ' \
        '"23 30" when you mean 23:30 (which is "30 23")'
    end
  end

  it 'orders nightly_reverse_geocoding_job before visit_suggesting_job in the daily cycle' do
    # Visit suggestion runs at 00:05 and uses point geodata for name suggestion.
    # Reverse-geocoding must run BEFORE that — either late the previous evening
    # or in the early hours of the same day, so geodata is populated.
    rg_cron = Fugit::Cron.parse(schedule.dig('nightly_reverse_geocoding_job', 'cron'))
    vs_cron = Fugit::Cron.parse(schedule.dig('visit_suggesting_job', 'cron'))

    # Reference moment: 00:00 of a fixed date in Sidekiq-cron's view (UTC).
    reference = Time.utc(2026, 5, 27, 0, 0, 0)
    rg_next = rg_cron.next_time(reference).utc
    vs_next = vs_cron.next_time(reference).utc

    # Both should fire within the next 24 h; RG should fire BEFORE visits.
    expect(rg_next - reference).to be < 24 * 3600,
      "expected reverse-geocoding to fire within 24h of #{reference}, got next at #{rg_next}"
    expect(vs_next - reference).to be < 24 * 3600,
      "expected visit-suggesting to fire within 24h of #{reference}, got next at #{vs_next}"
    expect(rg_next).to be < vs_next,
      "expected reverse-geocoding (#{rg_next}) to fire BEFORE visit-suggesting (#{vs_next}); " \
      'visit-suggesting needs fresh geodata to produce place names'
  end
end
