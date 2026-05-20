# frozen_string_literal: true

class DropLegacyLatLonFromPoints < ActiveRecord::Migration[8.0]
  def up
    Rails.logger.info '[DropLegacyLatLonFromPoints] starting'
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS latitude'
    execute 'ALTER TABLE points DROP COLUMN IF EXISTS longitude'
    Rails.logger.info '[DropLegacyLatLonFromPoints] done'
  end

  def down
    execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS latitude  numeric(10,6)'
    execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS longitude numeric(10,6)'
  end
end
