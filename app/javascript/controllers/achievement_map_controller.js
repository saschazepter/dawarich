import { Controller } from "@hotwired/stimulus"
import maplibregl from "maplibre-gl"
import { getMapStyle } from "maps_maplibre/utils/style_manager"

const queue = []
let active = 0
const MAX_CONCURRENT = 2

function schedule(task) {
  queue.push(task)
  pump()
}

function pump() {
  while (active < MAX_CONCURRENT && queue.length > 0) {
    active++
    const task = queue.shift()
    task().finally(() => {
      active--
      pump()
    })
  }
}

export default class extends Controller {
  static targets = ["host", "pin"]
  static values = {
    lat: Number,
    lng: Number,
    zoom: Number,
    markerLat: Number,
    markerLng: Number,
  }

  connect() {
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          this.observer.disconnect()
          schedule(() => this.render())
        }
      },
      { rootMargin: "300px" },
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    this.map?.remove()
    this.map = null
  }

  async render() {
    if (!this.element.isConnected || !this.hasHostTarget) return

    try {
      const style = await getMapStyle("light")
      await this.snapshot(style)
    } catch (error) {
      console.error("Achievement card map failed to render:", error)
    }
  }

  snapshot(style) {
    return new Promise((resolve) => {
      const host = this.hostTarget
      const map = new maplibregl.Map({
        container: host,
        style,
        center: [this.lngValue, this.latValue],
        zoom: this.zoomValue,
        interactive: false,
        attributionControl: false,
        preserveDrawingBuffer: true,
        fadeDuration: 0,
      })
      this.map = map

      const finish = () => {
        if (this.map === map) {
          this.placePin(map)
          const image = document.createElement("img")
          image.alt = ""
          image.src = map.getCanvas().toDataURL("image/png")
          map.remove()
          this.map = null
          host.replaceChildren(image)
        }
        resolve()
      }

      map.once("idle", finish)
      map.once("error", (event) => {
        console.error("Achievement card map error:", event.error)
        finish()
      })
    })
  }

  placePin(map) {
    if (!this.hasPinTarget || !this.hasMarkerLatValue) return

    const point = map.project([this.markerLngValue, this.markerLatValue])
    const canvas = map.getCanvas()
    const width = canvas.width / window.devicePixelRatio
    const height = canvas.height / window.devicePixelRatio
    if (width === 0 || height === 0) return

    const x = Math.min(Math.max((point.x / width) * 100, 6), 94)
    const y = Math.min(Math.max((point.y / height) * 100, 10), 92)
    this.pinTarget.style.left = `${x.toFixed(1)}%`
    this.pinTarget.style.top = `${y.toFixed(1)}%`
  }
}
