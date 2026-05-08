import { BaseLayer } from "./base_layer"

/**
 * Heatmap layer showing point density
 * Uses MapLibre's native heatmap for performance
 */
export class HeatmapLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "heatmap", ...options })
    this.opacity = options.opacity || 0.6
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || {
        type: "FeatureCollection",
        features: [],
      },
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: "heatmap",
        source: this.sourceId,
        paint: {
          // Fixed weight
          "heatmap-weight": 1,

          "heatmap-intensity": [
            "interpolate",
            ["linear"],
            ["zoom"],
            0,
            0.5,
            10,
            1,
            15,
            3,
            20,
            5,
          ],

          // Color ramp
          "heatmap-color": [
            "interpolate",
            ["linear"],
            ["heatmap-density"],
            0,
            "rgba(0,0,0,0)",
            0.05,
            "rgba(33,102,172,0.4)",
            0.2,
            "rgb(103,169,207)",
            0.4,
            "rgb(209,229,240)",
            0.6,
            "rgb(253,219,199)",
            0.8,
            "rgb(239,138,98)",
            1,
            "rgb(178,24,43)",
          ],

          // Radius in pixels, exponential growth
          "heatmap-radius": [
            "interpolate",
            ["exponential", 1.5],
            ["zoom"],
            10,
            15,
            13,
            30,
            15,
            50,
            20,
            120,
          ],

          // Visible when zoomed in, fades when zoomed out
          "heatmap-opacity": [
            "interpolate",
            ["linear"],
            ["zoom"],
            0,
            0.3,
            10,
            this.opacity,
            15,
            this.opacity,
          ],
        },
      },
    ]
  }
}
