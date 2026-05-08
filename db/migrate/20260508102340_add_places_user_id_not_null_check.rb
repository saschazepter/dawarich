# frozen_string_literal: true

class AddPlacesUserIdNotNullCheck < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :places, 'user_id IS NOT NULL',
                         name: 'places_user_id_null', validate: false, if_not_exists: true
  end
end
