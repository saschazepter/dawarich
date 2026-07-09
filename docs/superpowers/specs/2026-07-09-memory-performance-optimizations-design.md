# Memory And Performance Optimizations Design

## Goal

Reduce avoidable memory allocations, database transfer, repeated aggregate queries, and repeated browser transformations in high-cardinality point workflows without changing public response payloads, import/export formats, or map behavior.

## Scope

Implement the ten reproduced findings from the July 2026 performance review:

1. Remove unused trip coordinate materialization.
2. Calculate downloaded tempfile checksums without reading the entire file into a Ruby String.
3. Avoid instantiating point batches before the user-data export SQL reloads them.
4. Select only required columns in enqueue-only background sweeps.
5. Select only GPX-required point columns.
6. Exclude H3 payloads and other unused columns from stats aggregation reads.
7. Select only timestamp and coordinate fields during Immich enrichment.
8. Cap points API page size at 10,000 records.
9. Skip repeated range metadata queries on internal follow-up map pages.
10. Transform and publish point GeoJSON once after all map pages load.

The database-pool configuration observation is excluded because validation proved only a capacity risk, not an active bottleneck.

## Architecture

### Narrow Rails Data Paths

Existing services and jobs remain responsible for their current behavior. No new service layer, database migration, cache, or persistent state is introduced.

- `TripsController` stops running `set_coordinates` for show and edit because both pages use `trip.path` and no view consumes `@coordinates`.
- `Imports::SecureFileDownloader` computes the tempfile checksum from its path with a streaming digest API, preserving existing byte-size and checksum errors.
- `Users::ExportData::Points` uses relation batches and plucks only IDs before executing the existing export query. The JSONL output and batch query remain unchanged.
- Reverse-geocoding, country-ID migration, and place-name sweeps load only the scalar columns needed to enqueue work. Reverse geocoding retains the existing deduplication and cache-invalidation behavior.
- `Exports::Create` builds format-specific point scopes. GPX selects `id`, `lonlat`, `altitude`, `altitude_decimal`, `velocity`, `timestamp`, and `course`; GeoJSON retains its existing full serializer requirements except `raw_data`.
- Stats aggregation scopes select only `id`, `year`, `month`, `distance`, and `toponyms` where needed. User country/city cache scans select only `id` and `toponyms`.
- `Immich::EnrichScan` selects only `id`, `timestamp`, and `lonlat`, preserving timestamp ordering and interpolation behavior.

### Points API Metadata Control

`Api::V1::PointsController` adds `MAX_PER_PAGE = 10_000` and clamps any larger positive `per_page` value. Zero and negative values continue to use the current default of 100.

The index accepts `include_metadata=false`. Metadata remains enabled when the parameter is absent, preserving existing external behavior. When metadata is enabled, the controller keeps its current aggregate query, conditional GET handling, total-page headers, and Lite-plan count headers.

When metadata is disabled, the controller:

- skips the `COUNT/MAX` aggregate and `fresh_when` calculation;
- skips `X-Total-Pages`, `X-Total-Points-In-Range`, and `X-Scoped-Points`;
- still returns `X-Current-Page` and the normal JSON point payload;
- still applies authentication, plan scoping, anomaly filtering, import filtering, bounding-box filtering, ordering, page size clamping, and serialization.

### Map Client Pagination

`ApiClient#fetchPoints` accepts `include_metadata`, defaulting to true. It adds `include_metadata=false` to the request only when the caller opts out.

`ApiClient#fetchAllPoints` requests page one with metadata, reads its total-page count, and requests every later page with metadata disabled. Page results remain sorted before flattening, concurrent page fetching remains bounded by `maxConcurrent`, and progress callbacks retain their current loaded/page/percentage values.

Progressive `onBatch` delivery is removed. `Maplibre::DataLoader` continues to display numeric progress but converts the completed point collection to GeoJSON once, then updates point, heatmap, route, fog, and scratch sources through the existing final-load path.

## Compatibility

- Public API defaults remain unchanged unless a client explicitly sends `include_metadata=false`.
- Point JSON, ordering, filters, and authentication remain unchanged.
- Existing first-page and one-page map behavior remains unchanged apart from avoiding progressive point painting.
- Import, export, GPX, stats, trip, reverse-geocoding, and Immich result formats remain unchanged.
- No database or environment configuration changes are required.

## Error Handling

- Download size and checksum mismatches keep their existing exception messages.
- Oversized `per_page` values clamp to 10,000 rather than failing.
- Missing, zero, and negative `per_page` values retain existing behavior.
- Follow-up page failures continue to reject the complete map load through the existing `Promise.all` flow.
- Metadata opt-out never bypasses authorization, filtering, or plan restrictions.

## Testing

Every production change follows a red-green cycle with a focused performance contract:

- Trip request specs prove show and edit do not issue the unused coordinate projection query.
- Downloader specs trace public tempfile downloads and prove checksum verification does not call `IO#read`, while preserving valid, size-mismatch, and checksum-mismatch outcomes.
- User-data export specs prove monthly export does not instantiate point batches before the raw export query.
- Job specs capture SQL and prove enqueue sweeps use narrow projections while preserving enqueued jobs and cache invalidation.
- Export specs prove GPX queries exclude unrelated JSONB columns and generated GPX remains unchanged.
- Stats specs prove aggregation reads do not select H3 payloads and serialized output remains unchanged.
- Immich specs prove point matching uses a narrow projection and preserves nearest/interpolated matches.
- Points request specs prove `per_page` clamps at 10,000 and `include_metadata=false` skips aggregate SQL and total headers.
- A Node `node:test` specification imports `ApiClient`, stubs `fetch`, and proves only page one requests metadata, final results remain page-ordered, progress is accurate, and `onBatch` is not invoked.

Final verification runs focused RSpec and Node tests, the full RSpec suite, RuboCop on changed Ruby files, and Biome on changed JavaScript files.

## Out Of Scope

- Database-pool tuning.
- Cursor pagination or snapshot semantics.
- Server-side caching of point-range metadata.
- Streaming rewrites for whole JSON import formats.
- Changes to Redis topology, Docker resource limits, or Sidekiq process topology.
- Production performance claims without production profiling.

## Success Criteria

- All ten scoped findings are removed from their reproduced code paths.
- Existing public API behavior remains the default.
- Follow-up map pages execute no point-range metadata aggregate.
- A completed map load performs one point-to-GeoJSON conversion instead of one per page batch plus a final conversion.
- Focused and full verification pass with a clean worktree.
