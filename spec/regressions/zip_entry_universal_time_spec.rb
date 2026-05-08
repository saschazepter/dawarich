# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'Archive::Zipper writes a UTC-tagged mtime so cross-TZ extractors do not skew' do
  let(:payload_tempfile) do
    tempfile = Tempfile.new(['payload', '.gpx'], binmode: true)
    tempfile.write('<gpx></gpx>')
    tempfile.rewind
    tempfile
  end

  after { payload_tempfile.close! }

  it 'attaches a UniversalTime extra field with mtime equal to the current UTC epoch' do
    before_epoch = Time.now.to_i
    zipped = Archive::Zipper.wrap(payload_tempfile, entry_name: 'ride.gpx')
    after_epoch = Time.now.to_i

    begin
      entry = ::Zip::File.open(zipped.path) { |zf| zf.glob('ride.gpx').first }

      universal_time = entry.extra[:universaltime]
      message = 'Entry must carry a UniversalTime extra field so extractors interpret mtime as UTC.'
      expect(universal_time).not_to(be_nil, message)

      expect(universal_time.mtime.to_i).to be_between(before_epoch, after_epoch).inclusive
    ensure
      zipped.close!
    end
  end
end
