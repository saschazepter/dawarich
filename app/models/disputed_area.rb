# frozen_string_literal: true

# Territories claimed by more than one state. Achievements credit no country
# or subdivision for time spent inside them.
class DisputedArea < ApplicationRecord
  def self.covering_sql(geometry_sql)
    "EXISTS (SELECT 1 FROM disputed_areas d WHERE ST_Intersects(d.geom, #{geometry_sql}))"
  end
end
