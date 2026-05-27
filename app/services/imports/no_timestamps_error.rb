# frozen_string_literal: true

module Imports
  class NoTimestampsError < StandardError
    DEFAULT_MESSAGE = 'No timestamps found in the imported file. Dawarich tracks ' \
                      'timestamped location points; please re-export with timestamps included.'

    def initialize(message = DEFAULT_MESSAGE)
      super
    end
  end
end
