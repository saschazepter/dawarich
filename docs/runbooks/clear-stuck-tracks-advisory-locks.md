# Clear stuck `tracks:user:*` PG advisory locks

After deploying the Redis-backed `Tracks::PerUserLock` (replacing
`pg_try_advisory_lock`), legacy phantom advisory locks may still sit on
PgBouncer backends. They no longer block anything — production code now
uses Redis — but for hygiene, clear them once after deploy.

## Symptom (pre-deploy)

Sentry issue `DAWARICH-NT`: continuous
`Tracks::PerUserLock::AcquisitionTimeout` for one or more users (e.g.
`user_id=1410`), ~once every 30 s, for hours.

Root cause: PgBouncer transaction pooling routes each statement to a
different Postgres backend. `pg_try_advisory_lock` on backend A
succeeds, but the matching `pg_advisory_unlock` lands on backend B and
no-ops. The session lock on A is now orphaned for the lifetime of that
backend.

## After deploy

1. Verify `app/services/tracks/per_user_lock.rb` is on the running
   revision and Sidekiq workers have restarted.
2. Connect to the **primary** Postgres directly (not via PgBouncer):

   ```
   psql "$DAWARICH_DATABASE_URL_DIRECT"
   ```

3. Inspect remaining phantom locks (the legacy namespace was integer
   `classid = 4242`; the `with_advisory_lock` gem used a hashed
   `classid` — both are session-scoped):

   ```sql
   SELECT pid, locktype, classid, objid, granted
   FROM pg_locks
   WHERE locktype = 'advisory'
   ORDER BY pid;
   ```

4. Terminate the backends holding the phantom locks. This drops the
   advisory state along with the session and is safe — the new code
   path does not depend on Postgres advisory locks at all:

   ```sql
   SELECT pg_terminate_backend(pid)
   FROM pg_locks
   WHERE locktype = 'advisory';
   ```

5. Re-run the query in step 3 to confirm zero rows.

6. (Optional) Restart Sidekiq workers if any are still holding stale
   AR connections.

## Validation

- Sentry: `DAWARICH-NT` should stop receiving new events within one
  debounce cycle (~45 s) per affected user.
- Logs: `event=tracks.per_user_lock_contention` warnings should
  appear at most briefly, only when real contention exists (e.g.
  recalculate concurrent with realtime).
