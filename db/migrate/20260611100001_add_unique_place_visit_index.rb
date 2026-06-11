# frozen_string_literal: true

class AddUniquePlaceVisitIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :visits, %i[user_id place_id started_at],
              unique: true,
              where: 'place_id IS NOT NULL',
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'idx_visits_user_place_started_unique'
  end
end
