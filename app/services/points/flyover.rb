# frozen_string_literal: true

module Points
  module Flyover
    THRESHOLD_KMH = 500
    MS_TO_KMH = 3.6

    module_function

    def flyover?(point)
      (point[:velocity].to_f * MS_TO_KMH) > THRESHOLD_KMH
    end

    def exclude_sql
      "(velocity IS NULL OR velocity::float * #{MS_TO_KMH} <= #{THRESHOLD_KMH})"
    end
  end
end
