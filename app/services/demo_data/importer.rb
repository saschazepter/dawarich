# frozen_string_literal: true

class DemoData::Importer
  def initialize(user)
    @user = user
  end

  def call
    return { status: :exists } if @user.imports.exists?(demo: true)

    anchor = user_local_beginning_of_day

    ActiveRecord::Base.transaction do
      import = create_marker_import
      DemoData::PointsSeeder.new(@user, import, anchor).call
      DemoData::DerivativesSeeder.new(@user, anchor).call
    end

    invalidate_user_caches(anchor)

    { status: :created }
  rescue StandardError => e
    Rails.logger.error("[demo] seed failed for user #{@user.id}: #{e.class}: #{e.message}")
    { status: :error }
  end

  private

  def create_marker_import
    @user.imports.create!(
      name: 'Demo Data (Berlin + Prague)',
      source: :geojson,
      demo: true,
      status: :completed,
      processing_started_at: Time.current,
      skip_background_processing: true
    )
  end

  def user_local_beginning_of_day
    tz = @user.safe_settings.timezone.presence || 'UTC'
    Time.use_zone(tz) { Time.zone.now.beginning_of_day }
  end

  def invalidate_user_caches(anchor)
    months = [anchor.to_date.beginning_of_month, (anchor.to_date - 30).beginning_of_month].uniq
    months.each do |month_start|
      Rails.cache.delete(Timeline::MonthSummary.cache_key_for(@user, month_start))
    end
    Cache::InvalidateUserCaches.new(@user.id).call
  end
end
