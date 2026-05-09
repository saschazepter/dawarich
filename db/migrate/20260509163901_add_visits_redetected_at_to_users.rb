class AddVisitsRedetectedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :visits_redetected_at, :datetime
    add_index :users, :visits_redetected_at
  end
end
