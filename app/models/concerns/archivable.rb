# frozen_string_literal: true

module Archivable
  extend ActiveSupport::Concern

  included do
    belongs_to :raw_data_archive,
               class_name: 'Points::RawDataArchive',
               optional: true

    scope :archived, -> { where(raw_data_archived: true) }
    scope :not_archived, -> { where(raw_data_archived: false) }
    scope :with_archived_raw_data, lambda {
      includes(raw_data_archive: { file_attachment: :blob })
    }

    before_save :reset_archival_on_raw_data_change
  end

  # Main method: Get raw_data with fallback to archive
  # Use this instead of point.raw_data when you need archived data
  def raw_data_with_archive
    return raw_data if raw_data.present? || !raw_data_archived?

    fetch_archived_raw_data
  end

  # Restore archived data back to database column
  def restore_raw_data!(value)
    update!(
      raw_data: value,
      raw_data_archived: false,
      raw_data_archive_id: nil
    )
  end

  private

  def fetch_archived_raw_data
    # Check temporary restore cache first (for migrations)
    cached = check_temporary_restore_cache
    return cached if cached

    fetch_from_archive_file
  rescue StandardError => e
    handle_archive_fetch_error(e)
  end

  def reset_archival_on_raw_data_change
    return if new_record?
    return unless raw_data_archived? && will_save_change_to_raw_data?

    self.raw_data_archived = false
    self.raw_data_archive_id = nil
  end

  def check_temporary_restore_cache
    Rails.cache.read("raw_data:temp:#{user_id}:#{id}")
  end

  def fetch_from_archive_file
    return {} unless raw_data_archive&.file&.attached?

    # Download and search through JSONL
    compressed_content = Points::RawData::Encryption.decrypt_if_needed(
      raw_data_archive.file.blob.download, raw_data_archive
    )
    io = StringIO.new(compressed_content)
    gz = Zlib::GzipReader.new(io)

    begin
      result = nil
      gz.each_line do |line|
        data = JSON.parse(line)
        if data['id'] == id
          result = data['raw_data']
          break
        end
      end
      result || {}
    ensure
      gz.close
    end
  end

  def handle_archive_fetch_error(error)
    ExceptionReporter.call(error, "Failed to fetch archived raw_data for Point ID #{id}")

    {} # Graceful degradation
  end
end
