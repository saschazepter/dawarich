# frozen_string_literal: true

module Imports
  class ExtractionPolicy < ApplicationPolicy
    def create?
      user.present? &&
        record.user == user &&
        record.additional_data_extraction_supported?
    end
  end
end
