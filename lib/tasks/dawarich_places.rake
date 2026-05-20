# frozen_string_literal: true

namespace :dawarich do
  desc 'One-time orphan suggested-place cleanup for all users'
  task cleanup_suggested_places: :environment do
    User.in_batches(of: 100).each_with_index do |batch, i|
      batch.pluck(:id).each_with_index do |uid, j|
        Places::OrphanCleanupJob.set(wait: ((i * 100 + j) * 0.1).seconds).perform_later(uid)
      end
    end
    Rails.logger.info('[dawarich:cleanup_suggested_places] enqueued')
  end

  desc 'One-time backfill of legacy Place::DEFAULT_NAME rows'
  task backfill_place_names: :environment do
    Places::BulkNameFetchingJob.perform_later
    Rails.logger.info('[dawarich:backfill_place_names] enqueued')
  end
end
