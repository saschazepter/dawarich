import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static values = {
    linkId: String,
    showPhotos: Boolean,
  }

  connect() {
    this.initializeMap()
  }

  async initializeMap() {
    const style = await getMapStyle("light")

    this.map = new maplibregl.Map({
      container: this.element,
      style,
      center: [0, 0],
      zoom: 1,
      attributionControl: { compact: true },
      interactive: true,
    })

    this.map.addControl(
      new maplibregl.NavigationControl({ showCompass: false }),
      "top-right",
    )

    this.map.on("load", () => {
      this.loadPoints()
      if (this.showPhotosValue) this.loadPhotos()
    })
  }

  disconnect() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async loadPoints() {
    const res = await fetch(`/api/v1/shared/${this.linkIdValue}/points`)
    if (!res.ok) return
    const points = await res.json()
    if (!points.length) return

    const coords = points.map(([lon, lat]) => [lon, lat])

    this.map.addSource("route", {
      type: "geojson",
      data: {
        type: "Feature",
        geometry: { type: "LineString", coordinates: coords },
      },
    })

    this.map.addLayer({
      id: "route-line",
      type: "line",
      source: "route",
      paint: { "line-color": "#0ea5e9", "line-width": 3 },
    })

    const bounds = coords.reduce(
      (b, c) => b.extend(c),
      new maplibregl.LngLatBounds(coords[0], coords[0]),
    )
    this.map.fitBounds(bounds, { padding: 40, duration: 0 })
  }

  async loadPhotos() {
    const res = await fetch(`/api/v1/shared/${this.linkIdValue}/photos`)
    if (!res.ok) return
    const photos = await res.json()

    for (const photo of photos) {
      if (photo.latitude == null || photo.longitude == null) continue
      const el = document.createElement("img")
      el.src = photo.thumbnail_url
      el.className =
        "shared-photo-marker rounded-full border-2 border-white shadow"
      el.style.width = "32px"
      el.style.height = "32px"
      el.style.objectFit = "cover"
      new maplibregl.Marker({ element: el })
        .setLngLat([photo.longitude, photo.latitude])
        .addTo(this.map)
    }
  }
}
