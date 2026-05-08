# frozen_string_literal: true

module Visits
  class BulkDestroy
    attr_reader :user, :visit_ids, :errors

    def initialize(user, visit_ids)
      @user = user
      @visit_ids = visit_ids
      @errors = []
    end

    def call
      validate
      return false if errors.any?

      destroy_visits
    end

    private

    def validate
      return if visit_ids.present?

      errors << 'No visits selected'
    end

    def destroy_visits
      visits = user.visits.where(id: visit_ids)

      if visits.empty?
        errors << 'No matching visits found'
        return false
      end

      started_ats = visits.pluck(:started_at)
      destroyed_count = 0

      Visit.transaction do
        visits.find_each do |visit|
          visit.destroy!
          destroyed_count += 1
        end
      end

      { count: destroyed_count, started_ats: started_ats }
    end
  end
end
