# frozen_string_literal: true

module Visits
  class BulkDestroy
    MAX_VISIT_IDS = 500

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
      return errors << 'No visits selected' if visit_ids.blank?
      return if visit_ids.length <= MAX_VISIT_IDS

      errors << "Too many visits selected (max #{MAX_VISIT_IDS})"
    end

    def destroy_visits
      visits = user.scoped_visits.where(id: visit_ids).order(:id)
      ids = visits.pluck(:id)

      if ids.empty?
        errors << 'No matching visits found'
        return false
      end

      started_ats = visits.pluck(:started_at)

      Visit.transaction do
        Point.where(visit_id: ids).update_all(visit_id: nil)
        PlaceVisit.where(visit_id: ids).delete_all
        Visit.where(id: ids).delete_all
      end

      { count: ids.length, started_ats: started_ats }
    end
  end
end
