# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import for unsupported sources is not offered' do
  let(:user) { create(:user) }

  it 'marks GPX imports as unsupported via the migration backfill' do
    import = create(:import, user: user, source: :gpx)
    expect(import.additional_data_extraction_status).to be_in(%w[not_attempted unsupported])
  end

  it 'reports a GPX import as not supported by the translator' do
    import = build(:import, user: user, source: :gpx)
    expect(import.additional_data_extraction_supported?).to be false
  end

  it 'reports each Google source and Polarsteps as supported' do
    %i[google_records google_phone_takeout google_semantic_history polarsteps].each do |src|
      import = build(:import, user: user, source: src)
      expect(import.additional_data_extraction_supported?).to be(true), "expected #{src} supported"
    end
  end

  it 'translator returns no items for an unsupported source' do
    import = create(:import, user: user, source: :gpx)
    items = EnhancedImport::Translator.new(import).translate.to_a
    expect(items).to be_empty
  end
end
