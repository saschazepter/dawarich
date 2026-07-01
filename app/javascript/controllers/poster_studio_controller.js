import { Controller } from "@hotwired/stimulus"
import {
  PAPER_SIZES,
  resolveExportGeometry,
} from "poster_studio/data/paper_sizes"
import { loadTheme } from "poster_studio/data/theme_loader"
import {
  downloadBlob,
  pdfBlob,
  pngBlob,
  posterFilename,
} from "poster_studio/export/download"
import { encodePdf } from "poster_studio/export/pdf_encoder"
import { encodePng } from "poster_studio/export/png_encoder"
import { captureBounds } from "poster_studio/render/offscreen_map"
import { drawOverlay } from "poster_studio/render/overlay"
import { buildPosterStyle } from "poster_studio/render/style_builder"
import Flash from "./flash_controller"

const DIST_FACTOR = 3
const METERS_PER_DEGREE = 111320

// Client-side poster export. Reads the framed area, theme, and track straight
// from the live Map v2 controller and the poster tab's own hidden fields — no
// server round-trip, no edits to the existing map controllers.
export default class extends Controller {
  static targets = ["paperSize", "format", "button", "status"]
  static values = { dpi: { type: Number, default: 300 } }

  connect() {
    this.previewing = false
    this.savedStyle = null
    this.onTabChanged = (event) => {
      if (event.detail?.tab === "poster") this.enterPreview()
      else this.exitPreview()
    }
    this.onPanelClosed = () => this.exitPreview()
    this.onThemeChanged = () => {
      if (this.previewing) this.applyPreview()
    }
    document.addEventListener("map-panel:tab-changed", this.onTabChanged)
    document.addEventListener("map-panel:closed", this.onPanelClosed)
    document.addEventListener("poster-theme:changed", this.onThemeChanged)
  }

  disconnect() {
    document.removeEventListener("map-panel:tab-changed", this.onTabChanged)
    document.removeEventListener("map-panel:closed", this.onPanelClosed)
    document.removeEventListener("poster-theme:changed", this.onThemeChanged)
    this.exitPreview()
  }

  // Live preview: recolor the real Map v2 into the selected poster theme by
  // swapping its style, then restore the saved style on leaving the tab. Safe
  // because the map uses no addImage icons (setStyle round-trips cleanly) and
  // HTML markers live outside the style.
  async enterPreview() {
    const map = this.map
    if (!map || this.previewing) return
    this.previewing = true
    this.savedStyle = map.getStyle()
    await this.applyPreview()
  }

  async applyPreview() {
    const map = this.map
    if (!map || !this.previewing) return
    try {
      const theme = await loadTheme(this.themeKey)
      map.setStyle(buildPosterStyle({ theme, trackGeojson: this.trackGeojson }))
    } catch {
      this.exitPreview()
    }
  }

  exitPreview() {
    if (!this.previewing) return
    this.previewing = false
    const map = this.map
    if (map && this.savedStyle) map.setStyle(this.savedStyle)
    this.savedStyle = null
  }

  async download() {
    if (this.busy) return
    try {
      this.setBusy(true)
      const paperKey = this.paperSizeTarget.value
      const format = this.formatTarget.value
      const map = this.map
      if (!map) throw new Error("Map is not ready yet")

      const theme = await loadTheme(this.themeKey)
      const geometry = resolveExportGeometry(paperKey, this.dpiValue)
      this.setStatus(`Rendering ${paperKey} at ${geometry.effectiveDpi} dpi…`)

      const style = buildPosterStyle({ theme, trackGeojson: this.trackGeojson })
      const canvas = await captureBounds({
        style,
        bounds: this.posterBounds(map, paperKey),
        width: geometry.width,
        height: geometry.height,
      })
      drawOverlay(canvas, { theme, title: this.posterTitle })

      const paper = PAPER_SIZES[paperKey]
      if (format === "pdf") {
        const bytes = await encodePdf(canvas, {
          widthMm: paper.wmm,
          heightMm: paper.hmm,
        })
        downloadBlob(pdfBlob(bytes), posterFilename(theme, paperKey, "pdf"))
      } else {
        const { data } = canvas
          .getContext("2d")
          .getImageData(0, 0, canvas.width, canvas.height)
        const bytes = encodePng(
          new Uint8Array(data.buffer),
          canvas.width,
          canvas.height,
          geometry.effectiveDpi,
        )
        downloadBlob(pngBlob(bytes), posterFilename(theme, paperKey, "png"))
      }

      this.setStatus(
        geometry.steppedDown
          ? `Saved at ${geometry.effectiveDpi} dpi (device GL limit)`
          : "Saved",
      )
    } catch (error) {
      Flash.show("error", `Poster export failed: ${error.message}`)
      this.setStatus("")
    } finally {
      this.setBusy(false)
    }
  }

  posterBounds(map, paperKey) {
    const center = map.getCenter()
    const distance = Number.parseFloat(this.field("distance")) || 5000
    const heightMeters = (2 * distance) / DIST_FACTOR
    const paper = PAPER_SIZES[paperKey]
    const widthMeters = heightMeters * (paper.wmm / paper.hmm)
    const latDelta = heightMeters / 2 / METERS_PER_DEGREE
    const cosLat = Math.max(Math.cos((center.lat * Math.PI) / 180), 0.01)
    const lonDelta = widthMeters / 2 / (METERS_PER_DEGREE * cosLat)
    return [
      [center.lng - lonDelta, center.lat - latDelta],
      [center.lng + lonDelta, center.lat + latDelta],
    ]
  }

  get trackGeojson() {
    const layerManager = this.mapController?.layerManager
    const layerId = this.field("source") === "tracks" ? "tracks" : "routes"
    return (
      layerManager?.getLayer(layerId)?.data ?? {
        type: "FeatureCollection",
        features: [],
      }
    )
  }

  get themeKey() {
    return (
      this.posterRoot.querySelector('input[name="poster[theme]"]')?.value ||
      "blueprint"
    )
  }

  get posterTitle() {
    return (
      this.posterRoot.querySelector('input[name="poster[name]"]')?.value || ""
    )
  }

  field(name) {
    return this.posterRoot.querySelector(`input[name="poster[${name}]"]`)?.value
  }

  get posterRoot() {
    return this.element.closest('[data-tab-content="poster"]') || document
  }

  get mapController() {
    const container = document.getElementById("maps-maplibre-container")
    return (
      container &&
      this.application.getControllerForElementAndIdentifier(
        container,
        "maps--maplibre",
      )
    )
  }

  get map() {
    return this.mapController?.map
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  setBusy(value) {
    this.busy = value
    if (this.hasButtonTarget) this.buttonTarget.disabled = value
  }
}
