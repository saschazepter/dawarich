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
    Rails.logger.info(<<~MSG)
      [dawarich:cleanup_suggested_places] To verify the drain is complete, run:
        bin/rails runner 'puts Place.where(source: :photon, name: Place::DEFAULT_NAME, note: [nil, ""]).where.missing(:visits, :taggings).count'
      A return value of 0 means all orphan suggested places have been deleted and it is safe to schedule the place_visits drop.
    MSG
  end

  desc 'One-time backfill of legacy Place::DEFAULT_NAME rows'
  task backfill_place_names: :environment do
    Places::BulkNameFetchingJob.perform_later
    Rails.logger.info('[dawarich:backfill_place_names] enqueued')
  end

  desc 'Re-enqueue Places::NameFetchingJob for places stuck at DEFAULT_NAME (failed/retried out)'
  task resweep_default_named_places: :environment do
    cutoff = ENV.fetch('STUCK_AFTER_HOURS', '24').to_i.hours.ago
    max_wait = ENV.fetch('MAX_STAGGER_SECONDS', '600').to_i
    scope = Place.where(name: Place::DEFAULT_NAME, source: :photon)
                 .where('created_at < ?', cutoff)
                 .where('updated_at < ?', cutoff)
    count = 0
    scope.in_batches(of: 500) do |batch|
      batch.pluck(:id).each do |pid|
        Places::NameFetchingJob.set(wait: [count * 0.1, max_wait].min.seconds).perform_later(pid)
        count += 1
      end
    end
    Rails.logger.info("[dawarich:resweep_default_named_places] re-enqueued=#{count} cutoff=#{cutoff.iso8601}")
  end
end
