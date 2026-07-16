import { calculateDistance } from "./geometry"

export const SIMPLIFIED_POINTS_DISTANCE_METERS = 50
export const SIMPLIFIED_POINTS_TIME_MS = 20000

/**
 * Match Map v1's simplified point-rendering mode.
 * @param {Array} points - Array of point objects from API
 * @returns {Array} Simplified point array
 */
export function simplifyPointsForRendering(points) {
  if (!points.length) return points

  const simplified = [points[0]]
  let previousPoint = points[0]

  points.slice(1).forEach((point) => {
    const distance = calculateDistance(
      [previousPoint.longitude, previousPoint.latitude],
      [point.longitude, point.latitude],
    )
    const timeDiff =
      timestampMs(point.timestamp) - timestampMs(previousPoint.timestamp)

    if (
      distance >= SIMPLIFIED_POINTS_DISTANCE_METERS ||
      timeDiff >= SIMPLIFIED_POINTS_TIME_MS
    ) {
      simplified.push(point)
      previousPoint = point
    }
  })

  return simplified
}

function timestampMs(timestamp) {
  if (timestamp == null) return 0
  if (typeof timestamp === "number") {
    return timestamp < 10000000000 ? timestamp * 1000 : timestamp
  }

  const parsed = Date.parse(timestamp)
  return Number.isNaN(parsed) ? 0 : parsed
}

/**
 * Transform points array to GeoJSON FeatureCollection
 * @param {Array} points - Array of point objects from API
 * @param {Object} options
 * @param {boolean} options.simplified - Apply simplified point rendering
 * @returns {Object} GeoJSON FeatureCollection
 */
export function pointsToGeoJSON(points, options = {}) {
  const renderPoints = options.simplified
    ? simplifyPointsForRendering(points)
    : points

  return {
    type: "FeatureCollection",
    features: renderPoints.map((point) => ({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [point.longitude, point.latitude],
      },
      properties: {
        id: point.id,
        timestamp: point.timestamp,
        altitude: point.altitude,
        battery: point.battery,
        accuracy: point.accuracy,
        velocity: point.velocity,
        country_name: point.country_name,
      },
    })),
  }
}

/**
 * Format timestamp for display
 * @param {number|string} timestamp - Unix timestamp (seconds) or ISO 8601 string
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} Formatted date/time
 */
export function formatTimestamp(timestamp, timezone = "UTC") {
  // Handle different timestamp formats
  let date
  if (typeof timestamp === "string") {
    // ISO 8601 string
    date = new Date(timestamp)
  } else if (timestamp < 10000000000) {
    // Unix timestamp in seconds
    date = new Date(timestamp * 1000)
  } else {
    // Unix timestamp in milliseconds
    date = new Date(timestamp)
  }

  return date.toLocaleString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
    timeZone: timezone,
  })
}

/**
 * Format timestamp as time only (HH:MM)
 * @param {number|string} timestamp - Unix timestamp (seconds) or ISO 8601 string
 * @param {string} timezone - IANA timezone string (e.g., 'Europe/Berlin')
 * @returns {string} Formatted time (e.g., "14:30")
 */
export function formatTimeOnly(timestamp, timezone = "UTC") {
  if (!timestamp) return "--:--"

  let date
  if (typeof timestamp === "string") {
    date = new Date(timestamp)
  } else if (timestamp < 10000000000) {
    // Unix timestamp in seconds
    date = new Date(timestamp * 1000)
  } else {
    // Unix timestamp in milliseconds
    date = new Date(timestamp)
  }

  return date.toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone: timezone,
  })
}

/**
 * Escape HTML special characters to prevent XSS when using innerHTML.
 * @param {*} value - Value to escape (coerced to string)
 * @returns {string} HTML-safe string
 */
export function escapeHtml(value) {
  if (value == null) return ""
  const str = String(value)
  const div = document.createElement("div")
  div.textContent = str
  return div.innerHTML
}
