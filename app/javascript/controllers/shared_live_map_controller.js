import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

export default class extends Controller {
  static values = {
    linkId: String,
  }

  static targets = ["map", "status"]

  connect() {
    this.initializeMap()
  }

  async initializeMap() {
    const style = await getMapStyle("light")

    this.map = new maplibregl.Map({
      container: this.mapTarget,
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
      this.loadInitialPoint()
      this.subscribe()
    })
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  async loadInitialPoint() {
    const res = await fetch(`/api/v1/shared/${this.linkIdValue}/points`)
    if (!res.ok) return
    const points = await res.json()
    if (!points.length) {
      this.setStatus("Location unknown — waiting for an update…")
      return
    }
    const [lon, lat] = points[0]
    this.setStatus("")
    this.placeMarker(lon, lat)
  }

  subscribe() {
    this.consumer = createConsumer(
      `/cable?share_id=${encodeURIComponent(this.linkIdValue)}`,
    )
    this.subscription = this.consumer.subscriptions.create(
      { channel: "SharedLocationChannel", share_id: this.linkIdValue },
      {
        received: (data) => this.handleMessage(data),
      },
    )
  }

  handleMessage(data) {
    if (data.revoked) {
      this.setStatus("This live share has ended.")
      this.hideMarker()
      if (this.subscription) this.subscription.unsubscribe()
      return
    }
    if (data.masked) {
      this.setStatus("Location hidden.")
      this.hideMarker()
      return
    }
    if (data.lon != null && data.lat != null) {
      this.setStatus("")
      this.placeMarker(data.lon, data.lat)
    }
  }

  placeMarker(lon, lat) {
    if (this.marker) {
      this.marker.setLngLat([lon, lat])
    } else {
      this.marker = new maplibregl.Marker({ color: "#ef4444" })
        .setLngLat([lon, lat])
        .addTo(this.map)
    }
    this.map.easeTo({
      center: [lon, lat],
      zoom: Math.max(this.map.getZoom(), 13),
      duration: 600,
    })
  }

  hideMarker() {
    if (this.marker) {
      this.marker.remove()
      this.marker = null
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
