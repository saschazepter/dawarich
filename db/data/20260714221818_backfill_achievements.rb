# frozen_string_literal: true

class BackfillAchievements < ActiveRecord::Migration[8.0]
  def up
    Achievements::LoadRegions.new.call if Region.none?

    User.find_each do |user|
      Achievements::CheckJob.perform_later(user.id, notify: false)
    end
  end

  def down; end
end
