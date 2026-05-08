# frozen_string_literal: true

require 'rails_helper'
require 'smtp_config'

RSpec.describe SmtpConfig do
  describe '.smtp_settings' do
    it 'maps SMTP_* env vars onto the action_mailer smtp_settings hash' do
      env = {
        'SMTP_SERVER'   => 'smtp.office365.com',
        'SMTP_PORT'     => '587',
        'SMTP_DOMAIN'   => 'example.com',
        'SMTP_USERNAME' => 'noreply@example.com',
        'SMTP_PASSWORD' => 'secret'
      }

      result = described_class.smtp_settings(env)

      expect(result).to include(
        address:   'smtp.office365.com',
        port:      '587',
        domain:    'example.com',
        user_name: 'noreply@example.com',
        password:  'secret'
      )
    end

    it 'defaults authentication to :plain when SMTP_AUTHENTICATION is unset' do
      expect(described_class.smtp_settings({})[:authentication]).to eq(:plain)
    end

    it 'casts SMTP_AUTHENTICATION to a symbol from a whitelist' do
      expect(described_class.smtp_settings('SMTP_AUTHENTICATION' => 'login')[:authentication]).to eq(:login)
      expect(described_class.smtp_settings('SMTP_AUTHENTICATION' => 'cram_md5')[:authentication]).to eq(:cram_md5)
    end

    it 'rejects unsupported SMTP_AUTHENTICATION values at boot rather than at SMTP-connect time' do
      expect do
        described_class.smtp_settings('SMTP_AUTHENTICATION' => 'gssapi')
      end.to raise_error(ArgumentError, /SMTP_AUTHENTICATION/)
    end

    it 'enables STARTTLS by default and respects SMTP_STARTTLS=false' do
      expect(described_class.smtp_settings({})[:enable_starttls]).to be(true)
      expect(described_class.smtp_settings('SMTP_STARTTLS' => 'false')[:enable_starttls]).to be(false)
    end

    it 'defaults timeouts to 5 seconds and accepts overrides' do
      expect(described_class.smtp_settings({})).to include(open_timeout: 5, read_timeout: 5)
      expect(
        described_class.smtp_settings('SMTP_OPEN_TIMEOUT' => '25', 'SMTP_READ_TIMEOUT' => '30')
      ).to include(open_timeout: 25, read_timeout: 30)
    end

    it 'falls back to the 5-second default when a timeout env var is set but blank' do
      expect(
        described_class.smtp_settings('SMTP_OPEN_TIMEOUT' => '', 'SMTP_READ_TIMEOUT' => '   ')
      ).to include(open_timeout: 5, read_timeout: 5)
    end
  end

  describe '.mailer_url_options' do
    it 'reads DOMAIN as host and defaults protocol to https' do
      expect(
        described_class.mailer_url_options('DOMAIN' => 'dawarich.example')
      ).to eq(host: 'dawarich.example', protocol: 'https')
    end

    it 'lets self-hosters on plain HTTP override the protocol via APPLICATION_PROTOCOL' do
      expect(
        described_class.mailer_url_options('DOMAIN' => 'dawarich.lan', 'APPLICATION_PROTOCOL' => 'http')
      ).to eq(host: 'dawarich.lan', protocol: 'http')
    end
  end
end
