# frozen_string_literal: true

class ValidatePlacesUserIdNotNull < ActiveRecord::Migration[8.0]
  CONSTRAINT_NAME = 'places_user_id_null'

  def up
    validate_check_constraint :places, name: CONSTRAINT_NAME if check_constraint_exists?
    change_column_null :places, :user_id, false unless column_not_null?
    remove_check_constraint :places, name: CONSTRAINT_NAME, if_exists: true
  end

  def down
    add_check_constraint :places, 'user_id IS NOT NULL',
                         name: CONSTRAINT_NAME, validate: false, if_not_exists: true
    change_column_null :places, :user_id, true if column_not_null?
  end

  private

  def check_constraint_exists?
    connection.select_value(<<~SQL).to_i.positive?
      SELECT COUNT(*) FROM pg_constraint
      WHERE conname = '#{CONSTRAINT_NAME}' AND conrelid = 'places'::regclass
    SQL
  end

  def column_not_null?
    connection.select_value(<<~SQL) == 'NO'
      SELECT is_nullable FROM information_schema.columns
      WHERE table_name = 'places' AND column_name = 'user_id'
    SQL
  end
end
