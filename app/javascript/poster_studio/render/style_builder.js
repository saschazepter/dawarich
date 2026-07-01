import {
  DEFAULT_TILE_URL,
  PARK_KINDS,
  ROAD_BUCKETS,
  SOURCE_ID,
  SOURCE_MAX_ZOOM,
} from "../data/protomaps_schema.js"

export const TRACK_SOURCE_ID = "poster-track"

const EMPTY_FC = { type: "FeatureCollection", features: [] }

function zoomInterp(stops, scale = 1) {
  const flat = stops.flatMap(([z, w]) => [z, w * scale])
  return ["interpolate", ["linear"], ["zoom"], ...flat]
}

export function buildPosterStyle({
  theme,
  trackGeojson = EMPTY_FC,
  tileUrl = DEFAULT_TILE_URL,
  roadScale = 1,
  trackWidth = 1,
}) {
  if (!theme) throw new Error("buildPosterStyle requires a resolved theme")

  const roadLayers = ROAD_BUCKETS.map((bucket) => ({
    id: bucket.id,
    type: "line",
    source: SOURCE_ID,
    "source-layer": "roads",
    filter: bucket.filter,
    layout: { "line-cap": "round", "line-join": "round" },
    paint: {
      "line-color": theme.roads[bucket.themeKey] ?? theme.roads.default,
      "line-width": zoomInterp(bucket.widthStops, roadScale),
    },
  }))

  return {
    version: 8,
    sources: {
      [SOURCE_ID]: {
        type: "vector",
        tiles: [tileUrl],
        maxzoom: SOURCE_MAX_ZOOM,
        attribution:
          '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>',
      },
      [TRACK_SOURCE_ID]: { type: "geojson", data: trackGeojson },
    },
    layers: [
      {
        id: "poster_bg",
        type: "background",
        paint: { "background-color": theme.bg },
      },
      {
        id: "poster_earth",
        type: "fill",
        source: SOURCE_ID,
        "source-layer": "earth",
        paint: { "fill-color": theme.bg },
      },
      {
        id: "poster_parks",
        type: "fill",
        source: SOURCE_ID,
        "source-layer": "landuse",
        filter: ["in", "kind", ...PARK_KINDS],
        paint: { "fill-color": theme.parks },
      },
      {
        id: "poster_water",
        type: "fill",
        source: SOURCE_ID,
        "source-layer": "water",
        filter: ["==", "$type", "Polygon"],
        paint: { "fill-color": theme.water },
      },
      {
        id: "poster_water_lines",
        type: "line",
        source: SOURCE_ID,
        "source-layer": "water",
        filter: ["in", "kind", "river", "stream"],
        paint: {
          "line-color": theme.water,
          "line-width": zoomInterp([
            [8, 0.4],
            [12, 0.9],
            [16, 2.2],
          ]),
        },
      },
      ...roadLayers,
      {
        id: "poster_track_casing",
        type: "line",
        source: TRACK_SOURCE_ID,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": theme.casing,
          "line-width": zoomInterp(
            [
              [8, 3.2],
              [12, 4.6],
              [16, 7],
            ],
            trackWidth,
          ),
        },
      },
      {
        id: "poster_track",
        type: "line",
        source: TRACK_SOURCE_ID,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": theme.route,
          "line-width": zoomInterp(
            [
              [8, 1.5],
              [12, 2.6],
              [16, 4.6],
            ],
            trackWidth,
          ),
        },
      },
    ],
  }
}
