# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Videos::CallbackToken do
  describe '.generate / .verify' do
    it 'is deterministic for the same id and nonce' do
      token1 = described_class.generate(42, 'abc')
      token2 = described_class.generate(42, 'abc')
      expect(token1).to eq(token2)
    end

    it 'verifies a valid token' do
      token = described_class.generate(7, 'nonce')
      expect(described_class.verify(token, 7, 'nonce')).to be(true)
    end

    it 'rejects a token with mismatched id' do
      token = described_class.generate(7, 'nonce')
      expect(described_class.verify(token, 8, 'nonce')).to be(false)
    end

    it 'rejects a token with mismatched nonce' do
      token = described_class.generate(7, 'nonce')
      expect(described_class.verify(token, 7, 'other')).to be(false)
    end

    it 'rejects nil and empty tokens' do
      expect(described_class.verify(nil, 1, 'n')).to be(false)
      expect(described_class.verify('', 1, 'n')).to be(false)
    end

    it 'tolerates a malformed token without raising' do
      expect { described_class.verify('not-base64!@#', 1, 'n') }.not_to raise_error
      expect(described_class.verify('not-base64!@#', 1, 'n')).to be(false)
    end
  end
end
