/**
 * Persists the map's last viewport (center + zoom) in localStorage so the map
 * can reopen where the user left off instead of the zoomed-out globe — most
 * importantly when the selected date range has no data to fit bounds to.
 */

const STORAGE_KEY = "dawarich:map:lastView"

/**
 * @returns {{center: [number, number], zoom: number} | null}
 */
export function loadLastView() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
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
 */
export function saveView(map) {
  try {
    const center = map.getCenter()
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({ center: [center.lng, center.lat], zoom: map.getZoom() }),
    )
  } catch (_error) {
    // localStorage may be unavailable (private mode, quota) — non-fatal.
  }
}
