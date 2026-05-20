# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Apple web sign-in initializer' do
  let(:valid_p8) do
    OpenSSL::PKey::EC.generate('prime256v1').to_pem
  end

  let(:base64_p8) { Base64.strict_encode64(valid_p8) }

  around do |example|
    original = defined?(APPLE_WEB_SIGN_IN_PRIVATE_KEY) ? APPLE_WEB_SIGN_IN_PRIVATE_KEY : nil
    example.run
  ensure
    Object.send(:remove_const, :APPLE_WEB_SIGN_IN_PRIVATE_KEY) if defined?(APPLE_WEB_SIGN_IN_PRIVATE_KEY)
    Object.const_set(:APPLE_WEB_SIGN_IN_PRIVATE_KEY, original) unless original.nil?
  end

  it 'exposes APPLE_WEB_SIGN_IN_PRIVATE_KEY when env is set' do
    stub_const('ENV', ENV.to_hash.merge('APPLE_WEB_P8_BASE64' => base64_p8))
    load Rails.root.join('config/initializers/04_apple_web_sign_in.rb')
    expect(APPLE_WEB_SIGN_IN_PRIVATE_KEY).to be_a(OpenSSL::PKey::EC)
  end

  it 'leaves APPLE_WEB_SIGN_IN_PRIVATE_KEY nil when env is blank' do
    stub_const('ENV', ENV.to_hash.except('APPLE_WEB_P8_BASE64'))
    load Rails.root.join('config/initializers/04_apple_web_sign_in.rb')
    expect(APPLE_WEB_SIGN_IN_PRIVATE_KEY).to be_nil
  end

  it 'raises at boot when env is set but malformed' do
    stub_const('ENV', ENV.to_hash.merge('APPLE_WEB_P8_BASE64' => Base64.strict_encode64('not a key')))
    expect { load Rails.root.join('config/initializers/04_apple_web_sign_in.rb') }
      .to raise_error(OpenSSL::PKey::ECError)
  end
end
