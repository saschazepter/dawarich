# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SmtpConfig do
  describe '.smtp_settings' do
    it 'omits openssl_verify_mode when SMTP_OPENSSL_VERIFY_MODE is unset' do
      expect(described_class.smtp_settings({})).not_to have_key(:openssl_verify_mode)
    end

    it 'passes through none' do
      settings = described_class.smtp_settings('SMTP_OPENSSL_VERIFY_MODE' => 'none')

      expect(settings[:openssl_verify_mode]).to eq('none')
    end

    it 'passes through peer' do
      settings = described_class.smtp_settings('SMTP_OPENSSL_VERIFY_MODE' => 'peer')

      expect(settings[:openssl_verify_mode]).to eq('peer')
    end

    it 'normalizes case and whitespace' do
      settings = described_class.smtp_settings('SMTP_OPENSSL_VERIFY_MODE' => '  NONE  ')

      expect(settings[:openssl_verify_mode]).to eq('none')
    end

    it 'raises on an unsupported value' do
      expect { described_class.smtp_settings('SMTP_OPENSSL_VERIFY_MODE' => 'bogus') }
        .to raise_error(ArgumentError, /SMTP_OPENSSL_VERIFY_MODE/)
    end
  end
end
