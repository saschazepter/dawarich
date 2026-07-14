# frozen_string_literal: true

class SeedAchievementRegionsAndBackfill < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:regions)

    Achievements::LoadRegions.new.call if Region.none?

    user_ids = (User.active.pluck(:id) + User.trial.pluck(:id)).uniq
    user_ids.each_slice(200).with_index do |batch, index|
      batch.each do |user_id|
        Achievements::CheckJob.set(wait: index * 5.minutes).perform_later(user_id, notify: false)
      end
    end
  end

  def down; end
end
