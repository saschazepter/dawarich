# frozen_string_literal: true

class DataMigrations::StartBackfillPointsToponymsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    scope = Point.where.not(reverse_geocoded_at: nil).where(country_name: nil)

    scope.find_each(batch_size: 1000) do |point|
      DataMigrations::BackfillPointsToponymsJob.perform_later(point.id)
    end
  end
end
