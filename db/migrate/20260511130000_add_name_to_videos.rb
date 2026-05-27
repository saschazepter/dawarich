class AddNameToVideos < ActiveRecord::Migration[8.0]
  def change
    add_column :videos, :name, :string, limit: 200
  end
end
