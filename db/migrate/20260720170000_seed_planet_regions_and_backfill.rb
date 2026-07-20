# frozen_string_literal: true

class SeedPlanetRegionsAndBackfill < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:regions)

    Region.where.not('code LIKE ?', '%-%').delete_all
    return if Country.none?

    Achievements::LoadRegions.new.call

    user_ids = (User.active.pluck(:id) + User.trial.pluck(:id)).uniq
    user_ids.each_slice(200).with_index do |batch, index|
      batch.each do |user_id|
        Achievements::CheckJob.set(wait: index * 5.minutes).perform_later(user_id, notify: false)
      end
    end
  end

  def down; end
end
