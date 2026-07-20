# frozen_string_literal: true

# Regenerates config/achievements/planet.yml and lib/assets/admin1_world.geojson.
# Never hand-edit those files.
#
# Natural Earth codes subdivisions at a finer level than ISO 3166-2 first level in
# ~30 countries (FR départements vs régions, GB districts vs nations). Stage 1 derives
# a child -> first-level lookup from ISO so mapshaper can dissolve them upwards.
#
# 1. bin/rails runner script/generate_planet_achievements.rb parents iso_3166-2.json
#
#    iso_3166-2.json comes from the Debian iso-codes snapshot cited in
#    lib/assets/world_administrative_subdivisions.csv's README (commit a9e9e319):
#    https://salsa.debian.org/iso-codes-team/iso-codes/-/raw/<sha>/data/iso_3166-2.json
#
# 2. Download Natural Earth 10m admin-1 states/provinces, then reduce it:
#
#      npx mapshaper ne_10m_admin_1_states_provinces.shp \
#        -filter 'iso_3166_2 && iso_3166_2 !== "" && iso_3166_2.indexOf("~") === -1' \
#        -join lib/assets/iso_3166_2_parents.csv keys=iso_3166_2,code \
#        -filter 'first_level' \
#        -dissolve first_level \
#        -rename-fields iso_3166_2=first_level \
#        -simplify 12% keep-shapes \
#        -o format=geojson precision=0.001 admin1_first_level.geojson
#
#    -dissolve is mandatory: Natural Earth splits subdivisions across multiple features
#    (PH-MNL has 17) and the loader keeps one row per code.
#    keep-shapes is mandatory: without it -simplify drops exclaves such as Bremerhaven.
#
# 3. bin/rails runner script/generate_planet_achievements.rb build admin1_first_level.geojson

require 'csv'

module Achievements
  class PlanetParents
    PARENTS_PATH = 'lib/assets/iso_3166_2_parents.csv'

    def initialize(iso_json)
      @iso_json = iso_json
    end

    def call
      entries = Oj.load(File.read(iso_json))['3166-2']
      parents = entries.to_h { |entry| [entry['code'], entry['parent']] }
      path = Rails.root.join(PARENTS_PATH)

      CSV.open(path, 'w') do |csv|
        csv << %w[code first_level]
        parents.each_key do |code|
          first_level = resolve(code, parents)
          csv << [code, first_level] if first_level
        end
      end

      puts "wrote #{path} (#{entries.size} ISO entries, #{parents.count { |_, p| p }} children)"
    end

    private

    attr_reader :iso_json

    def resolve(code, parents)
      seen = parents[code]
      return code if seen.nil?

      parents.key?(seen) && parents[seen].nil? ? seen : nil
    end
  end

  class PlanetGenerator
    COVERAGE_GATE = 0.8
    CSV_PATH = 'lib/assets/world_administrative_subdivisions.csv'
    NAMES_PATH = 'lib/assets/ne_admin1_names.csv'
    YAML_PATH = 'config/achievements/planet.yml'
    GEOJSON_PATH = 'lib/assets/admin1_world.geojson'

    ART_SQL = <<~SQL
      SELECT c.iso_a2,
             ST_Y(ST_Centroid(d.g)) AS lat, ST_X(ST_Centroid(d.g)) AS lon,
             ST_XMax(d.g) - ST_XMin(d.g) AS w, ST_YMax(d.g) - ST_YMin(d.g) AS h
      FROM countries c
      CROSS JOIN LATERAL (
        SELECT (ST_Dump(c.geom)).geom AS g
        ORDER BY ST_Area((ST_Dump(c.geom)).geom) DESC
        LIMIT 1
      ) d
      WHERE c.iso_a2 <> '-99'
    SQL

    def initialize(source_geojson)
      @source_geojson = source_geojson
    end

    def call
      report
      write_yaml
      write_geojson
    end

    private

    attr_reader :source_geojson

    def rows
      @rows ||= CSV.read(Rails.root.join(CSV_PATH), headers: true)
    end

    def features
      @features ||= Oj.load(File.read(source_geojson))['features']
    end

    def available_codes
      @available_codes ||= features.map { |feature| feature['properties']['iso_3166_2'] }.to_set
    end

    def known_country_codes
      @known_country_codes ||= country_art.keys.to_set
    end

    def country_art
      @country_art ||= ActiveRecord::Base.connection.select_all(ART_SQL).to_h do |row|
        span = [row['w'], row['h']].max
        zoom = (Math.log2(360.0 / span) - 1).clamp(0.5, 9.0)

        [row['iso_a2'], { 'lat' => row['lat'].round(3), 'lon' => row['lon'].round(3),
                          'zoom' => zoom.round(1) }]
      end
    end

    def continents
      @continents ||= rows.group_by { |row| row['region'] }.sort.to_h do |region, region_rows|
        [region, { 'countries' => countries_for(region_rows) }]
      end
    end

    def countries_for(region_rows)
      region_rows
        .group_by { |row| row['country_code'] }
        .select { |code, _| known_country_codes.include?(code) }
        .sort_by { |_, country_rows| country_rows.first['country_name'] }
        .to_h do |code, country_rows|
          [code, { 'name' => country_rows.first['country_name'],
                   'art' => country_art.fetch(code),
                   'subdivisions' => subdivisions_for(country_rows) }]
        end
    end

    def subdivisions_for(country_rows)
      declared = country_rows.filter_map { |row| row['subdivision_code'] }
      return {} if declared.empty?

      matched = declared.select { |code| available_codes.include?(code) }
      return {} if matched.size < declared.size * COVERAGE_GATE

      country_rows
        .select { |row| matched.include?(row['subdivision_code']) }
        .sort_by { |row| row['subdivision_code'] }
        .to_h do |row|
          code = row['subdivision_code']
          [code, english_names.fetch(code, row['subdivision_name'])]
        end
    end

    def english_names
      @english_names ||= CSV.read(Rails.root.join(NAMES_PATH), headers: true)
                            .reverse_each
                            .to_h { |row| [row['iso_3166_2'], row['name_en']] }
                            .compact
    end

    def gridded_codes
      @gridded_codes ||= continents.values
                                   .flat_map { |continent| continent['countries'].values }
                                   .flat_map { |country| country['subdivisions'].keys }
                                   .to_set
    end

    def report
      declared = rows.map { |row| row['country_code'] }.uniq
      dropped = declared.reject { |code| known_country_codes.include?(code) }
      countries = continents.values.flat_map { |c| c['countries'].to_a }
      flat = countries.reject { |_, country| country['subdivisions'].any? }.map(&:first)

      puts "countries: #{declared.size - dropped.size} kept, #{dropped.size} dropped " \
           "(no countries row): #{dropped.sort.join(', ')}"
      puts "gridded: #{countries.size - flat.size} · flat: #{flat.size} (#{flat.sort.join(', ')})"
      puts "subdivisions: #{gridded_codes.size} of #{rows.count { |r| r['subdivision_code'] }}"
    end

    def write_yaml
      path = Rails.root.join(YAML_PATH)
      header = "# Generated by script/generate_planet_achievements.rb — do not hand-edit.\n"

      File.write(path, header + { 'continents' => continents }.to_yaml(line_width: -1))
      puts "wrote #{path}"
    end

    def write_geojson
      path = Rails.root.join(GEOJSON_PATH)
      kept = features.select { |f| gridded_codes.include?(f['properties']['iso_3166_2']) }

      File.write(path, Oj.dump({ 'type' => 'FeatureCollection', 'features' => kept }, mode: :compat))
      puts "wrote #{path} (#{kept.size} features, #{File.size(path) / 1024} KB)"
    end
  end
end

mode, source = ARGV
abort("no such file: #{source}") if source.blank? || !File.exist?(source)

case mode
when 'parents' then Achievements::PlanetParents.new(source).call
when 'build' then Achievements::PlanetGenerator.new(source).call
else abort('usage: generate_planet_achievements.rb parents|build <file>')
end
