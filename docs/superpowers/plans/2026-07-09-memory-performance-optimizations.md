# Memory And Performance Optimizations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove ten reproduced memory, query, and browser-processing inefficiencies without changing public API defaults or user-visible data formats.

**Architecture:** Keep every optimization inside its existing controller, service, job, serializer, or client. Narrow database projections and stream file checksums on the backend; let internal map pagination skip metadata after page one; remove progressive full-dataset GeoJSON rebuilding on the frontend.

**Tech Stack:** Ruby 3.4.9, Rails 8.1.3, PostgreSQL/PostGIS, RSpec, JavaScript ES modules, Node 18 `node:test`, Biome.

## Global Constraints

- Base all work on `origin/dev` in branch `perf/reduce-memory-query-overhead`.
- Public API metadata and conditional GET behavior remain enabled when `include_metadata` is absent.
- `include_metadata=false` skips only aggregate metadata and related headers; it never skips authentication, plan scoping, filters, ordering, pagination, or serialization.
- Clamp positive points API page sizes to exactly 10,000; zero and negative values continue to use 100.
- Preserve point JSON, import/export formats, GPX content, stats content, trip rendering, geocoding deduplication, cache invalidation, and Immich matching behavior.
- Do not add a database migration, cache, dependency, service object, or database-pool change.
- Follow red-green TDD for every task and commit each task independently.

---

### Task 1: Remove Request-Path Memory Spikes

**Files:**
- Modify: `spec/requests/trips_spec.rb`
- Modify: `app/controllers/trips_controller.rb:8-10,139-144`
- Modify: `spec/services/imports/secure_file_downloader_spec.rb`
- Modify: `app/services/imports/secure_file_downloader.rb:149-169`

**Interfaces:**
- Consumes: Existing trip show/edit routes and `Imports::SecureFileDownloader#download_to_temp_file`.
- Produces: Trip pages that use only `trip.path`; tempfile checksum verification that retains the existing return path and exception messages.

- [ ] **Step 1: Add failing trip query-contract specs**

Add this helper near the top of `spec/requests/trips_spec.rb` inside the outer describe:

```ruby
def capture_sql
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
  queries
end
```

Add one example under `GET /show` and one under `GET /edit`:

```ruby
it 'does not load the unused raw point coordinate projection' do
  queries = capture_sql { get trip_url(trip) }

  expect(queries.none? { |sql| sql.include?('"points"."latitude", "points"."longitude", "points"."battery"') }).to be(true)
end
```

```ruby
it 'does not load the unused raw point coordinate projection' do
  queries = capture_sql { get edit_trip_url(trip) }

  expect(queries.none? { |sql| sql.include?('"points"."latitude", "points"."longitude", "points"."battery"') }).to be(true)
end
```

- [ ] **Step 2: Verify the trip specs fail for the intended query**

Run: `bundle exec rspec spec/requests/trips_spec.rb`

Expected: the two new examples fail because `set_coordinates` issues the eight-column point projection.

- [ ] **Step 3: Remove unused coordinate loading**

Delete this callback from `TripsController`:

```ruby
before_action :set_coordinates, only: %i[show edit]
```

Delete the complete private `set_coordinates` method. Keep `@coordinates = []` in `new`; it is unrelated form initialization.

- [ ] **Step 4: Verify the trip specs pass**

Run: `bundle exec rspec spec/requests/trips_spec.rb`

Expected: all examples pass.

- [ ] **Step 5: Add a failing bounded-read checksum spec**

Under `describe '#download_to_temp_file'`, add:

```ruby
context 'with a file larger than the digest read buffer' do
  let(:file_content) { 'x' * 1.megabyte }

  it 'never reads the complete tempfile into one Ruby String' do
    read_sizes = []
    trace = TracePoint.new(:c_return) do |event|
      next unless event.method_id == :read
      next unless event.return_value.is_a?(String)

      read_sizes << event.return_value.bytesize
    end

    path = trace.enable { subject.download_to_temp_file }

    expect(read_sizes).not_to include(file_content.bytesize)
  ensure
    File.unlink(path) if path && File.exist?(path)
  end
end
```

- [ ] **Step 6: Verify the checksum spec fails for the full read**

Run: `bundle exec rspec spec/services/imports/secure_file_downloader_spec.rb`

Expected: the new example fails because `temp_file.read` returns a 1 MB String.

- [ ] **Step 7: Stream the tempfile checksum**

Replace the checksum block in `verify_temp_file_integrity` with:

```ruby
expected_checksum = storage_attachment.blob.checksum
actual_checksum = Base64.strict_encode64(Digest::MD5.file(temp_file.path).digest)
temp_file.rewind
```

Keep the existing comparison and exception text unchanged.

- [ ] **Step 8: Verify Task 1 and lint changed Ruby files**

Run: `bundle exec rspec spec/requests/trips_spec.rb spec/services/imports/secure_file_downloader_spec.rb`

Expected: all examples pass.

Run: `bundle exec rubocop app/controllers/trips_controller.rb app/services/imports/secure_file_downloader.rb spec/requests/trips_spec.rb spec/services/imports/secure_file_downloader_spec.rb`

Expected: no offenses.

- [ ] **Step 9: Commit Task 1**

```bash
git add app/controllers/trips_controller.rb app/services/imports/secure_file_downloader.rb spec/requests/trips_spec.rb spec/services/imports/secure_file_downloader_spec.rb
git commit -m "Reduce trip and download memory usage"
```

---

### Task 2: Avoid Model Instantiation In Batch Enqueue And Export Paths

**Files:**
- Modify: `spec/services/users/export_data/points_spec.rb`
- Modify: `app/services/users/export_data/points.rb:32-65`
- Modify: `spec/jobs/points/nightly_reverse_geocoding_job_spec.rb`
- Modify: `app/jobs/points/nightly_reverse_geocoding_job.rb`
- Modify: `spec/jobs/data_migrations/start_settings_points_country_ids_job_spec.rb`
- Modify: `app/jobs/data_migrations/start_settings_points_country_ids_job.rb`
- Modify: `spec/jobs/places/bulk_name_fetching_job_spec.rb`
- Modify: `app/jobs/places/bulk_name_fetching_job.rb`

**Interfaces:**
- Consumes: Existing export SQL, Active Job arguments, `Point#async_reverse_geocode`, and cache invalidation service.
- Produces: Identical export files and enqueued jobs without loading wide models when only IDs are needed.

- [ ] **Step 1: Add a failing export instantiation contract**

In the monthly-file context of `spec/services/users/export_data/points_spec.rb`, add:

```ruby
it 'does not instantiate Point models before running the export query' do
  instantiated = 0
  callback = lambda do |_name, _start, _finish, _id, payload|
    instantiated += payload[:record_count] if payload[:class_name] == 'Point'
  end

  ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') do
    monthly_service.call
  end

  expect(instantiated).to eq(0)
end
```

- [ ] **Step 2: Verify the export spec fails**

Run: `bundle exec rspec spec/services/users/export_data/points_spec.rb`

Expected: the new example reports one instantiated `Point` per exported row.

- [ ] **Step 3: Replace model batches with relation batches**

Change `stream_to_monthly_files` to iterate as follows:

```ruby
user.points.in_batches(of: BATCH_SIZE) do |batch|
  point_ids = batch.pluck(:id)
  batch_sql = ActiveRecord::Base.sanitize_sql_array([build_batch_query, point_ids])
  result = ActiveRecord::Base.connection.exec_query(batch_sql, 'Points Export Batch')

  result.each do |row|
    point_hash = build_point_hash(row)
    next unless point_hash

    month_key = extract_month_key(row)
    writer = monthly_writer_for(month_key)
    writer.puts(point_hash.to_json)

    processed += 1
    log_progress(processed, total_count) if (processed % PROGRESS_LOG_INTERVAL).zero?
  end

  percentage = (processed.to_f / total_count * 100).round(1)
  Rails.logger.debug "Exported #{processed}/#{total_count} points (#{percentage}%)"
end
```

- [ ] **Step 4: Add failing narrow-query contracts to the three job specs**

In each job spec, subscribe to `sql.active_record` around `described_class.perform_now`, select the SQL statement for the target table, and assert the projection:

```ruby
queries = []
callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
  described_class.perform_now
end
```

For nightly reverse geocoding, assert:

```ruby
point_query = queries.find { |sql| sql.include?('FROM "points"') && sql.include?('reverse_geocoded_at') }
expect(point_query).to include('"points"."id", "points"."user_id"')
expect(point_query).not_to include('"points".*')
```

For country-ID migration, add:

```ruby
it 'selects only point IDs while enqueueing' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
    described_class.perform_now
  end

  point_queries = queries.select { |sql| sql.include?('FROM "points"') }
  expect(point_queries).not_to be_empty
  expect(point_queries).to all(include('"points"."id"'))
  expect(point_queries).to all(satisfy { |sql| !sql.include?('"points".*') })
end
```

For place-name fetching, add:

```ruby
it 'selects only place IDs while enqueueing' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
    described_class.perform_now
  end

  place_queries = queries.select { |sql| sql.include?('FROM "places"') }
  expect(place_queries).not_to be_empty
  expect(place_queries).to all(include('"places"."id"'))
  expect(place_queries).to all(satisfy { |sql| !sql.include?('"places".*') })
end
```

- [ ] **Step 5: Verify all three job specs fail on wide SELECTs**

Run: `bundle exec rspec spec/jobs/points/nightly_reverse_geocoding_job_spec.rb spec/jobs/data_migrations/start_settings_points_country_ids_job_spec.rb spec/jobs/places/bulk_name_fetching_job_spec.rb`

Expected: the new projection examples fail because current queries select complete records.

- [ ] **Step 6: Narrow all enqueue sweeps**

Use this relation in `Points::NightlyReverseGeocodingJob`:

```ruby
Point.not_reverse_geocoded.select(:id, :user_id).find_each(batch_size: 1000) do |point|
  point.async_reverse_geocode(force: true)
  processed_user_ids.add(point.user_id)
end
```

Use batched ID plucks in `DataMigrations::StartSettingsPointsCountryIdsJob`:

```ruby
Point.where(country_id: nil).in_batches do |batch|
  batch.pluck(:id).each do |point_id|
    DataMigrations::SetPointsCountryIdsJob.perform_later(point_id)
  end
end
```

Use the same shape in `Places::BulkNameFetchingJob`:

```ruby
Place.where(name: Place::DEFAULT_NAME).in_batches do |batch|
  batch.pluck(:id).each do |place_id|
    Places::NameFetchingJob.perform_later(place_id)
  end
end
```

Update the existing mocked `find_each` example in the nightly job spec so its relation double expects `select(:id, :user_id)` before `find_each`, or replace that implementation-detail example with the SQL projection contract.

- [ ] **Step 7: Verify Task 2 and lint**

Run: `bundle exec rspec spec/services/users/export_data/points_spec.rb spec/jobs/points/nightly_reverse_geocoding_job_spec.rb spec/jobs/data_migrations/start_settings_points_country_ids_job_spec.rb spec/jobs/places/bulk_name_fetching_job_spec.rb`

Expected: all examples pass and existing job counts/arguments remain unchanged.

Run: `bundle exec rubocop app/services/users/export_data/points.rb app/jobs/points/nightly_reverse_geocoding_job.rb app/jobs/data_migrations/start_settings_points_country_ids_job.rb app/jobs/places/bulk_name_fetching_job.rb spec/services/users/export_data/points_spec.rb spec/jobs/points/nightly_reverse_geocoding_job_spec.rb spec/jobs/data_migrations/start_settings_points_country_ids_job_spec.rb spec/jobs/places/bulk_name_fetching_job_spec.rb`

Expected: no offenses.

- [ ] **Step 8: Commit Task 2**

```bash
git add app/services/users/export_data/points.rb app/jobs/points/nightly_reverse_geocoding_job.rb app/jobs/data_migrations/start_settings_points_country_ids_job.rb app/jobs/places/bulk_name_fetching_job.rb spec/services/users/export_data/points_spec.rb spec/jobs/points/nightly_reverse_geocoding_job_spec.rb spec/jobs/data_migrations/start_settings_points_country_ids_job_spec.rb spec/jobs/places/bulk_name_fetching_job_spec.rb
git commit -m "Narrow batch enqueue and export queries"
```

---

### Task 3: Narrow GPX, Stats, And Immich Reads

**Files:**
- Modify: `spec/services/exports/create_spec.rb`
- Modify: `app/services/exports/create.rb:35-48`
- Modify: `spec/serializers/stats_serializer_spec.rb`
- Modify: `app/serializers/stats_serializer.rb:33-45`
- Modify: `spec/models/user_spec.rb`
- Modify: `app/models/user.rb:233-277`
- Modify: `spec/services/immich/enrich_scan_spec.rb`
- Modify: `app/services/immich/enrich_scan.rb:52-70`

**Interfaces:**
- Consumes: Existing GPX/GeoJSON serializers, stats JSON contract, user country/city caches, and Immich matching algorithm.
- Produces: Identical outputs from narrower Active Record projections.

- [ ] **Step 1: Add failing SQL projection specs**

Use this complete GPX example in the GPX context of `spec/services/exports/create_spec.rb`:

```ruby
it 'selects only fields required by GPX serialization' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { create_export }

  point_query = queries.find { |sql| sql.include?('FROM "points"') && sql.include?('"points"."lonlat"') }
  expect(point_query).to include(
    '"points"."id"', '"points"."lonlat"', '"points"."altitude"',
    '"points"."altitude_decimal"', '"points"."velocity"',
    '"points"."timestamp"', '"points"."course"'
  )
  expect(point_query).not_to include('raw_data', 'geodata', 'motion_data')
end
```

Add this example to the stats-present context in `spec/serializers/stats_serializer_spec.rb`:

```ruby
it 'does not load H3 payloads while aggregating stats' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { serializer }

  row_queries = queries.select { |sql| sql.include?('FROM "stats"') && !sql.include?('SUM(') }
  expect(row_queries).not_to be_empty
  expect(row_queries).to all(satisfy { |sql| !sql.include?('"stats".*') })
  expect(row_queries).to all(satisfy { |sql| !sql.include?('h3_hex_ids') })
end
```

Add this example to both `#countries_visited` and `#cities_visited` contexts in `spec/models/user_spec.rb`, changing only the call in the subscribed block:

```ruby
it 'selects only fields required for toponym aggregation' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
    user.countries_visited
  end

  row_query = queries.find { |sql| sql.include?('FROM "stats"') }
  expect(row_query).to include('"stats"."id", "stats"."toponyms"')
  expect(row_query).not_to include('"stats".*')
  expect(row_query).not_to include('h3_hex_ids')
end
```

Add this separate example to `#cities_visited`:

```ruby
it 'selects only fields required for toponym aggregation' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
    user.cities_visited
  end

  row_query = queries.find { |sql| sql.include?('FROM "stats"') }
  expect(row_query).to include('"stats"."id", "stats"."toponyms"')
  expect(row_query).not_to include('"stats".*')
  expect(row_query).not_to include('h3_hex_ids')
end
```

Add this example to the matching context in `spec/services/immich/enrich_scan_spec.rb`:

```ruby
it 'selects only fields required for temporal matching' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { service.call }

  point_query = queries.find { |sql| sql.include?('FROM "points"') }
  expect(point_query).to include(
    '"points"."id"', '"points"."timestamp"', '"points"."lonlat"'
  )
  expect(point_query).not_to include('"points".*', 'raw_data', 'geodata', 'motion_data')
end
```

- [ ] **Step 2: Verify the new projection specs fail**

Run: `bundle exec rspec spec/services/exports/create_spec.rb spec/serializers/stats_serializer_spec.rb spec/models/user_spec.rb spec/services/immich/enrich_scan_spec.rb`

Expected: all new projection examples fail against wide selects.

- [ ] **Step 3: Add format-specific export scopes**

Replace `time_framed_points` with:

```ruby
def time_framed_points
  points = user.points.where(timestamp: start_at.to_i..end_at.to_i)

  case file_format.to_sym
  when :gpx
    points.select(:id, :lonlat, :altitude, :altitude_decimal, :velocity, :timestamp, :course)
  when :json
    points.select(Point.column_names - %w[raw_data])
  else
    points
  end
end
```

Do not alter serializer dispatch or error handling.

- [ ] **Step 4: Narrow stats relations**

Change `StatsSerializer#yearly_stats` to start from:

```ruby
user.stats.select(:id, :year, :month, :distance, :toponyms).group_by(&:year)
```

Change both user cache scans to:

```ruby
stats.select(:id, :toponyms).find_each do |stat|
```

Keep aggregation and sorting behavior unchanged.

- [ ] **Step 5: Narrow Immich point matching**

Add the projection before ordering:

```ruby
points = user.points
             .where(timestamp: min_ts..max_ts)
             .where.not(lonlat: nil)
             .select(:id, :timestamp, :lonlat)
             .order(:timestamp)
             .to_a
```

- [ ] **Step 6: Verify Task 3 and lint**

Run: `bundle exec rspec spec/services/exports/create_spec.rb spec/serializers/stats_serializer_spec.rb spec/models/user_spec.rb spec/services/immich/enrich_scan_spec.rb`

Expected: all examples pass with unchanged serialized and matching results.

Run: `bundle exec rubocop app/services/exports/create.rb app/serializers/stats_serializer.rb app/models/user.rb app/services/immich/enrich_scan.rb spec/services/exports/create_spec.rb spec/serializers/stats_serializer_spec.rb spec/models/user_spec.rb spec/services/immich/enrich_scan_spec.rb`

Expected: no offenses.

- [ ] **Step 7: Commit Task 3**

```bash
git add app/services/exports/create.rb app/serializers/stats_serializer.rb app/models/user.rb app/services/immich/enrich_scan.rb spec/services/exports/create_spec.rb spec/serializers/stats_serializer_spec.rb spec/models/user_spec.rb spec/services/immich/enrich_scan_spec.rb
git commit -m "Narrow export stats and Immich queries"
```

---

### Task 4: Bound Point Pages And Make Metadata Optional

**Files:**
- Modify: `spec/requests/api/v1/points_caching_spec.rb`
- Modify: `app/controllers/api/v1/points_controller.rb:3-83`

**Interfaces:**
- Produces: `Api::V1::PointsController::MAX_PER_PAGE = 10_000`; query parameter `include_metadata`, default true.
- Consumed by Task 5: `ApiClient#fetchPoints` sends `include_metadata=false` on follow-up pages.

- [ ] **Step 1: Add failing metadata opt-out request specs**

Add these examples to `points_caching_spec.rb`:

```ruby
it 'skips range aggregates and total headers when metadata is disabled' do
  queries = []
  callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }

  ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
    get "/api/v1/points?api_key=#{user.api_key}&#{range}&include_metadata=false"
  end

  expect(response).to have_http_status(:ok)
  expect(response.headers['X-Current-Page']).to eq('1')
  expect(response.headers['X-Total-Pages']).to be_nil
  expect(response.headers['X-Total-Points-In-Range']).to be_nil
  expect(response.headers['X-Scoped-Points']).to be_nil
  expect(queries.none? { |sql| sql.match?(/COUNT\(\*\).*MAX\(timestamp\)/i) }).to be(true)
end

it 'keeps metadata enabled by default' do
  get "/api/v1/points?api_key=#{user.api_key}&#{range}"

  expect(response.headers['ETag']).to be_present
  expect(response.headers['X-Total-Pages']).to eq('1')
end
```

- [ ] **Step 2: Add a failing 10,000-row page cap spec**

Add this complete example:

```ruby
it 'caps oversized page requests at 10,000 points' do
  base_timestamp = 2.days.ago.to_i + 1
  now = Time.current
  rows = 9_998.times.map do |offset|
    {
      user_id: user.id,
      timestamp: base_timestamp + offset,
      lonlat: 'POINT(13.4 52.5)',
      created_at: now,
      updated_at: now
    }
  end
  Point.insert_all!(rows)

  get "/api/v1/points?api_key=#{user.api_key}&#{range}&per_page=999999"

  expect(response).to have_http_status(:ok)
  expect(response.parsed_body.size).to eq(10_000)
  expect(response.headers['X-Total-Pages']).to eq('2')
end
```

- [ ] **Step 3: Verify API specs fail**

Run: `bundle exec rspec spec/requests/api/v1/points_caching_spec.rb`

Expected: metadata opt-out still runs the aggregate and oversized pages return more than 10,000 rows.

- [ ] **Step 4: Implement metadata gating and page clamping**

Add:

```ruby
MAX_PER_PAGE = 10_000
```

Add a private predicate:

```ruby
def include_metadata?
  ActiveModel::Type::Boolean.new.cast(params.fetch(:include_metadata, true))
end
```

Wrap the aggregate, `fresh_when`, total counts, `X-Total-Pages`, and Lite-plan count headers in `if include_metadata?`. Always set `X-Current-Page` after pagination.

Clamp page size with:

```ruby
per_page = params[:per_page].to_i
per_page = 100 unless per_page.positive?
per_page = [per_page, MAX_PER_PAGE].min
```

Do not call `total_pages`, `count`, or any aggregate when metadata is disabled.

- [ ] **Step 5: Verify API behavior and lint**

Run: `bundle exec rspec spec/requests/api/v1/points_caching_spec.rb spec/requests/api/v1/points_spec.rb`

Expected: all examples pass, including existing ETag invalidation behavior.

Run: `bundle exec rubocop app/controllers/api/v1/points_controller.rb spec/requests/api/v1/points_caching_spec.rb`

Expected: no offenses.

- [ ] **Step 6: Commit Task 4**

```bash
git add app/controllers/api/v1/points_controller.rb spec/requests/api/v1/points_caching_spec.rb
git commit -m "Bound point pages and optional metadata"
```

---

### Task 5: Fetch Map Metadata Once And Render Points Once

**Files:**
- Create: `spec/javascript/maps_maplibre/api_client_test.mjs`
- Modify: `package.json`
- Modify: `app/javascript/maps_maplibre/services/api_client.js:12-193`
- Modify: `app/javascript/controllers/maps/maplibre/data_loader.js:154-172`

**Interfaces:**
- Consumes: Task 4's `include_metadata=false` query parameter.
- Produces: `ApiClient#fetchPoints({ ..., include_metadata = true })`; `fetchAllPoints` returns the existing `{ points, totalPointsInRange }` shape without progressive `onBatch` calls.

- [ ] **Step 1: Create a failing Node unit test**

Create `spec/javascript/maps_maplibre/api_client_test.mjs`:

```javascript
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../../app/javascript/maps_maplibre/services/api_client.js", import.meta.url),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { ApiClient } = await import(moduleUrl)

test("fetchAllPoints requests metadata once and returns ordered points", async (t) => {
  const originalFetch = globalThis.fetch
  const urls = []
  const batches = []
  const progress = []
  t.after(() => {
    globalThis.fetch = originalFetch
  })

  globalThis.fetch = async (url) => {
    urls.push(url)
    const page = Number(new URL(url, "http://example.test").searchParams.get("page"))
    const headers = page === 1 ? { "X-Total-Pages": "3", "X-Total-Points-In-Range": "3" } : {}
    return new Response(JSON.stringify([{ id: page }]), { status: 200, headers })
  }

  const client = new ApiClient("secret")
  const result = await client.fetchAllPoints({
    start_at: 1,
    end_at: 2,
    maxConcurrent: 2,
    onProgress: (value) => progress.push(value),
    onBatch: (value) => batches.push(value),
  })

  assert.deepEqual(result.points.map(({ id }) => id), [1, 2, 3])
  assert.equal(new URL(urls[0], "http://example.test").searchParams.has("include_metadata"), false)
  assert.equal(new URL(urls[1], "http://example.test").searchParams.get("include_metadata"), "false")
  assert.equal(new URL(urls[2], "http://example.test").searchParams.get("include_metadata"), "false")
  assert.equal(batches.length, 0)
  assert.equal(progress.at(-1).loaded, 3)
  assert.equal(progress.at(-1).progress, 1)
})
```

Add this script to `package.json`:

```json
"scripts": {
  "test:js": "node --test spec/javascript/maps_maplibre/api_client_test.mjs"
}
```

- [ ] **Step 2: Verify the Node test fails for repeated metadata and batches**

Run: `npm run test:js`

Expected: FAIL because follow-up URLs lack `include_metadata=false` and `onBatch` is called.

- [ ] **Step 3: Make metadata control explicit in `fetchPoints`**

Change the signature to:

```javascript
async fetchPoints({
  start_at,
  end_at,
  page = 1,
  per_page = 1000,
  include_metadata = true,
  signal,
})
```

After constructing `params`, add:

```javascript
if (!include_metadata) params.append("include_metadata", "false")
```

- [ ] **Step 4: Request metadata only on page one and remove batch delivery**

Remove `onBatch` from the documented and destructured `fetchAllPoints` options. Delete all three `onBatch` callback blocks. Pass `include_metadata: false` in every `fetchPoints` call for pages 2 and later:

```javascript
this.fetchPoints({
  start_at,
  end_at,
  page,
  per_page: 1000,
  include_metadata: false,
})
```

Keep page sorting, flattening, concurrency, return shape, and progress callbacks unchanged.

Remove the `onBatch` option from the `fetchAllPoints` call in `data_loader.js`. Keep the final `pointsToGeoJSON` and layer updates at lines 283-317; that is now the single conversion and publication path.

- [ ] **Step 5: Verify JavaScript behavior and formatting**

Run: `npm run test:js`

Expected: one passing test.

Run: `npx @biomejs/biome check app/javascript/maps_maplibre/services/api_client.js app/javascript/controllers/maps/maplibre/data_loader.js spec/javascript/maps_maplibre/api_client_test.mjs package.json`

Expected: no errors. If Biome reports formatting changes, run the same command with `--write`, inspect the diff, and rerun the check.

- [ ] **Step 6: Commit Task 5**

```bash
git add package.json app/javascript/maps_maplibre/services/api_client.js app/javascript/controllers/maps/maplibre/data_loader.js spec/javascript/maps_maplibre/api_client_test.mjs
git commit -m "Avoid repeated map point processing"
```

---

### Task 6: Final Verification And Pull Request

**Files:**
- Verify only; do not add generated coverage, logs, Swagger output, or temporary benchmark files.

**Interfaces:**
- Consumes: Commits from Tasks 1-5.
- Produces: Reviewed branch and GitHub pull request targeting `dev`.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bundle exec rspec spec/requests/trips_spec.rb spec/services/imports/secure_file_downloader_spec.rb spec/services/users/export_data/points_spec.rb spec/jobs/points/nightly_reverse_geocoding_job_spec.rb spec/jobs/data_migrations/start_settings_points_country_ids_job_spec.rb spec/jobs/places/bulk_name_fetching_job_spec.rb spec/services/exports/create_spec.rb spec/serializers/stats_serializer_spec.rb spec/models/user_spec.rb spec/services/immich/enrich_scan_spec.rb spec/requests/api/v1/points_caching_spec.rb spec/requests/api/v1/points_spec.rb
npm run test:js
```

Expected: all focused RSpec and Node tests pass.

- [ ] **Step 2: Run full verification**

Run: `bundle exec rspec`

Expected: zero failures.

Run: `bundle exec rubocop` and `npx @biomejs/biome ci .`

Expected: zero blocking offenses or errors.

- [ ] **Step 3: Review branch scope**

Run `git status --short`, `git diff origin/dev...HEAD --stat`, `git diff origin/dev...HEAD`, and `git log --oneline origin/dev..HEAD`.

Expected: only the approved design, plan, production files, and tests are changed; no secrets, runtime artifacts, unrelated edits, or generated files are present.

- [ ] **Step 4: Dispatch whole-branch code review**

Review the complete `origin/dev...HEAD` diff for correctness, API compatibility, query regressions, missing tests, and unintended scope. Fix every Critical or Important finding through a failing test first, then rerun covering tests and review again.

- [ ] **Step 5: Push and open the PR**

Push `perf/reduce-memory-query-overhead` to `origin` and create a GitHub pull request with base `dev`. The PR description must include a concise summary, grouped backend/API/frontend changes, and every verification command actually run. Do not claim production latency or percentage improvements.
