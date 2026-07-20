# frozen_string_literal: true

class DataMigrations::DropLegacyLatLonJob < ApplicationJob
  queue_as :data_migrations

  LOCK_TIMEOUT = '5s'

  # Losing the lock race is the expected case on a busy instance, so back off
  # and try again over the next few hours rather than reporting a failure.
  retry_on ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 25
  retry_on ActiveRecord::StatementTimeout, wait: :polynomially_longer, attempts: 25

  def perform
    connection = ActiveRecord::Base.connection
    return unless legacy_columns?(connection)

    connection.execute("SET lock_timeout = '#{LOCK_TIMEOUT}'")
    connection.execute('ALTER TABLE points DROP COLUMN IF EXISTS latitude, DROP COLUMN IF EXISTS longitude')

    Rails.logger.info('[DataMigrations::DropLegacyLatLon] dropped legacy points.latitude / points.longitude')
  ensure
    connection&.execute('RESET lock_timeout')
  end

  private

  def legacy_columns?(connection)
    connection.column_exists?(:points, :latitude) || connection.column_exists?(:points, :longitude)
  end
end
