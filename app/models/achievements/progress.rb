# frozen_string_literal: true

module Achievements
  class Progress < ApplicationRecord
    self.table_name = 'achievement_progresses'

    belongs_to :user

    validates :achievement_key, presence: true, uniqueness: { scope: :user_id }
  end
end
