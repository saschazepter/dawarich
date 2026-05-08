# frozen_string_literal: true

module EnhancedImport
  module Writers
    class VisitWriter
      def initialize(user)
        @user = user
      end

      def upsert(extracted, place)
        return nil if place.nil?

        existing = Visit.where(
          user_id: @user.id,
          started_at: extracted.started_at,
          place_id: place.id
        ).first
        return [existing, false] if existing

        visit = Visit.create!(
          user_id: @user.id,
          place_id: place.id,
          started_at: extracted.started_at,
          ended_at: extracted.ended_at,
          duration: extracted.duration_seconds,
          name: extracted.name.presence || place.name,
          status: 0
        )
        [visit, true]
      rescue ActiveRecord::RecordNotUnique
        existing = Visit.where(
          user_id: @user.id,
          started_at: extracted.started_at,
          place_id: place.id
        ).first
        [existing, false]
      end
    end
  end
end
