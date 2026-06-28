/**
 * Persists the map's last viewport (center + zoom) in localStorage so the map
 * can reopen where the user left off instead of the zoomed-out globe — most
 * importantly when the selected date range has no data to fit bounds to.
 *
 * The storage key is scoped per user so a shared browser doesn't leak one
 * account's last viewport into another's. The scope is hashed (not stored raw)
 * so the API key never appears in the key name.
 */

const STORAGE_PREFIX = "dawarich:map:lastView"

function hashScope(scope) {
  let hash = 5381
  for (let i = 0; i < scope.length; i++) {
    hash = ((hash << 5) + hash + scope.charCodeAt(i)) | 0
  }
  return (hash >>> 0).toString(36)
}

function storageKey(scope) {
  return scope ? `${STORAGE_PREFIX}:${hashScope(scope)}` : STORAGE_PREFIX
}

/**
 * @param {string} [scope] - Per-user scope (e.g. the API key)
 * @returns {{center: [number, number], zoom: number} | null}
 */
export function loadLastView(scope) {
  try {
    const raw = localStorage.getItem(storageKey(scope))
    if (!raw) return null

    const view = JSON.parse(raw)
    const center = view?.center
    const zoom = view?.zoom

    const valid =
      Array.isArray(center) &&
      center.length === 2 &&
      Number.isFinite(center[0]) &&
      Number.isFinite(center[1]) &&
      Number.isFinite(zoom)

    return valid ? { center, zoom } : null
  } catch (_error) {
    return null
  }
}

/**
 * @param {maplibregl.Map} map
 * @param {string} [scope] - Per-user scope (e.g. the API key)
 */
export function saveView(map, scope) {
  try {
    const center = map.getCenter()
    localStorage.setItem(
      storageKey(scope),
      JSON.stringify({ center: [center.lng, center.lat], zoom: map.getZoom() }),
    )
  } catch (_error) {
    // localStorage may be unavailable (private mode, quota) — non-fatal.
  }
}
