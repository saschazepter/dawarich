import maplibregl from "maplibre-gl"
import { trimOutlierCoords } from "maps_maplibre/utils/geometry"

// Live map inside the poster frame: pan and zoom stay enabled, rotation and
// pitch are disabled everywhere — the export reproduces the view from its
// axis-aligned bounds, which a rotated viewport would break.
export function createPreviewMap({ container, style, bounds }) {
  const map = new maplibregl.Map({
    container,
    style,
    ...(bounds
      ? { bounds, fitBoundsOptions: { padding: 24, animate: false } }
      : { center: [0, 0], zoom: 1 }),
    attributionControl: false,
    fadeDuration: 0,
    dragRotate: false,
    pitchWithRotate: false,
  })
  map.touchZoomRotate.disableRotation()
  map.keyboard.disableRotation()
  return map
}

export function collectCoords(geojson) {
  const coords = []
  for (const feature of geojson?.features ?? []) {
    const geometry = feature.geometry
    if (!geometry) continue
    if (geometry.type === "LineString") coords.push(...geometry.coordinates)
    else if (geometry.type === "MultiLineString")
      for (const line of geometry.coordinates) coords.push(...line)
    else if (geometry.type === "Point") coords.push(geometry.coordinates)
  }
  return coords
}

// Outlier-trimmed bounds of the track FeatureCollection, or null when empty.
export function trackBounds(geojson) {
  const coords = collectCoords(geojson)
  if (coords.length === 0) return null

  const kept = trimOutlierCoords(coords)
  let [minLng, minLat] = kept[0]
  let [maxLng, maxLat] = kept[0]
  for (const [lng, lat] of kept) {
    if (lng < minLng) minLng = lng
    if (lng > maxLng) maxLng = lng
    if (lat < minLat) minLat = lat
    if (lat > maxLat) maxLat = lat
  }
  if (minLng === maxLng && minLat === maxLat) {
    return [
      [minLng - 0.01, minLat - 0.01],
      [maxLng + 0.01, maxLat + 0.01],
    ]
  }
  return [
    [minLng, minLat],
    [maxLng, maxLat],
  ]
}

// Largest frame with the given aspect that fits the stage with breathing room.
export function fitFrame(stage, aspect) {
  const maxWidth = stage.clientWidth * 0.82
  const maxHeight = stage.clientHeight * 0.86
  let width = maxWidth
  let height = width / aspect
  if (height > maxHeight) {
    height = maxHeight
    width = height * aspect
  }
  return { width: Math.round(width), height: Math.round(height) }
}
