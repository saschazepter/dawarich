# frozen_string_literal: true

class DataMigrations::BackfillPointsToponymsJob < ApplicationJob
  queue_as :data_migrations

  def perform(point_id)
    point = Point.find_by(id: point_id)
    return if point.nil?
    return if point.read_attribute(:country_name).present? && point.read_attribute(:city).present?

    if geodata_toponyms(point).present?
      fill_from_geodata(point)
    else
      ReverseGeocodingJob.perform_later('Point', point.id, force: true)
    end
  end

  private

  def geodata_toponyms(point)
    properties = point.geodata.is_a?(Hash) ? point.geodata['properties'] : nil
    return {} unless properties.is_a?(Hash)

    { country: properties['country'].presence, city: properties['city'].presence }.compact
  end

  def fill_from_geodata(point)
    toponyms = geodata_toponyms(point)
    country = Country.find_by(name: toponyms[:country]) if toponyms[:country]

    point.update_columns(
      city: toponyms[:city] || point.read_attribute(:city),
      country_name: toponyms[:country] || point.read_attribute(:country_name),
      country_id: country&.id || point.country_id
    )
  end
end
