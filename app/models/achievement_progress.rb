# frozen_string_literal: true

class AchievementProgress < ApplicationRecord
  belongs_to :user

  validates :achievement_key, presence: true, uniqueness: { scope: :user_id }
end
