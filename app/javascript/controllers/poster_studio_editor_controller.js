import { Controller } from "@hotwired/stimulus"
import {
  DEFAULT_FONT_KEY,
  ensurePosterFont,
  fontByKey,
  POSTER_FONTS,
} from "poster_studio/data/fonts"
import {
  DEFAULT_LAYOUT_ID,
  LAYOUT_CATEGORIES,
  layoutById,
  resolveLayoutGeometry,
} from "poster_studio/data/layouts"
import {
  extendTokens,
  loadThemeTokens,
  resolveTheme,
} from "poster_studio/data/theme_loader"
import { downloadBlob } from "poster_studio/export/download"
import { drawOverlay } from "poster_studio/render/overlay"
import { buildPosterStyle } from "poster_studio/render/style_builder"
import { formatCoords } from "poster_studio/render/text_layout"
import { exportPoster, studioFilename } from "poster_studio/ui/exporter"
import {
  collectCoords,
  createPreviewMap,
  fitFrame,
  trackBounds,
} from "poster_studio/ui/preview"
import Flash from "./flash_controller"

const RESTYLE_DEBOUNCE_MS = 150
const DEFAULT_HIDDEN = ["buildings", "rail", "boundaries"]
const METERS_PER_DEGREE = 111320
// Sidecar frame semantics: it renders ±distance/3 vertically, so covering
// the studio's visible height needs distance = 3 × half-height in meters.
const SIDECAR_DISTANCE_FACTOR = 1.5
const SIDECAR_DISTANCE_RANGE = [500, 20000]
function toLocalInput(date) {
  const pad = (n) => String(n).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

// Full-screen WYSIWYG poster editor: a live MapLibre map inside a
// poster-shaped frame, restyled by the same buildPosterStyle the export
// renders, with typography drawn by the same overlay pass — so what the
// preview shows is what the download produces.
export default class extends Controller {
  static targets = [
    "stage",
    "frame",
    "mapContainer",
    "overlay",
    "layoutSelect",
    "layoutDims",
    "swatch",
    "themeLabel",
    "token",
    "tokenValue",
    "textToggle",
    "titleInput",
    "subtitleInput",
    "coordsToggle",
    "fontSelect",
    "trackOpacity",
    "trackOpacityLabel",
    "summary",
    "format",
    "dpi",
    "dpiField",
    "downloadButton",
    "status",
    "saveButton",
    "saveNotice",
    "saveForm",
    "saveName",
    "saveTheme",
    "saveLat",
    "saveLon",
    "saveDistance",
    "saveStartAt",
    "saveEndAt",
    "saveSource",
    "saveOpacity",
    "dateStart",
    "dateEnd",
  ]
  static values = { fonts: Object }

  connect() {
    // The map page wraps content in a z-index:20 stacking context that would
    // trap the overlay under the navbar — portal to <body>. Moving the node
    // re-runs connect (Stimulus disconnect/reconnect), hence the guard.
    if (this.element.parentElement !== document.body) {
      document.body.appendChild(this.element)
      return
    }
    this.onOpen = () => this.open()
    document.addEventListener("poster-studio:open", this.onOpen)
    this.onResize = () => this.resizeFrame()
    this.populateLayouts()
    this.populateFonts()
  }

  disconnect() {
    document.removeEventListener("poster-studio:open", this.onOpen)
    this.teardown()
  }

  async open() {
    if (!this.element.classList.contains("hidden")) return
    this.element.classList.remove("hidden")
    window.addEventListener("resize", this.onResize)

    try {
      this.hidden ??= new Set(DEFAULT_HIDDEN)
      if (!this.tokens) await this.seedTheme(this.initialThemeKey())
      if (!this.subtitleInputTarget.value)
        this.subtitleInputTarget.value = this.dateRangeLabel()
      this.seedDateInputs()

      this.resizeFrame()
      await this.loadFonts()
      this.createMap()
      this.updateSummary()
    } catch (error) {
      Flash.show("error", `Poster studio failed to open: ${error.message}`)
      this.close()
    }
  }

  close() {
    window.removeEventListener("resize", this.onResize)
    this.teardown()
    this.element.classList.add("hidden")
  }

  teardown() {
    clearTimeout(this.restyleTimer)
    this.previewMap?.remove()
    this.previewMap = null
  }

  createMap() {
    this.teardown()
    const bounds = trackBounds(this.trackGeojson) ?? this.mainMapBounds()
    this.previewMap = createPreviewMap({
      container: this.mapContainerTarget,
      style: this.posterStyle(),
      bounds,
    })
    this.previewMap.on("move", () => this.redrawOverlay())
    this.previewMap.on("moveend", () => this.syncSaveAvailability())
    this.previewMap.once("load", () => {
      this.redrawOverlay()
      this.syncSaveAvailability()
    })
  }

  // ===== Live restyle =====

  posterStyle() {
    return buildPosterStyle({
      theme: this.resolvedTheme,
      trackGeojson: this.trackGeojson,
      extras: true,
      hiddenCategories: [...this.hidden],
      trackOpacity: this.trackOpacityValue(),
    })
  }

  get resolvedTheme() {
    return resolveTheme(this.tokens)
  }

  scheduleRestyle() {
    clearTimeout(this.restyleTimer)
    this.restyleTimer = setTimeout(() => {
      this.previewMap?.setStyle(this.posterStyle())
      this.redrawOverlay()
    }, RESTYLE_DEBOUNCE_MS)
  }

  // ===== Theme =====

  initialThemeKey() {
    return this.swatchTargets[0]?.dataset.key || "blueprint"
  }

  async seedTheme(key) {
    const raw = await loadThemeTokens(key)
    this.tokens = { ...extendTokens(raw), ...raw }
    this.themeBase = key
    this.themeName =
      this.swatchTargets.find((el) => el.dataset.key === key)?.dataset.name ||
      raw.name ||
      key
    this.markSwatch(key)
    if (this.hasThemeLabelTarget)
      this.themeLabelTarget.textContent = this.themeName
    this.tokenTargets.forEach((input) => {
      const value = this.tokens[input.dataset.token]
      if (value) input.value = value
      this.syncTokenLabel(input)
    })
  }

  async pickTheme(event) {
    try {
      await this.seedTheme(event.currentTarget.dataset.key)
      this.scheduleRestyle()
      this.updateSummary()
    } catch (error) {
      Flash.show("error", `Failed to load theme: ${error.message}`)
    }
  }

  tokenChanged(event) {
    this.tokens[event.target.dataset.token] = event.target.value
    this.syncTokenLabel(event.target)
    this.scheduleRestyle()
  }

  syncTokenLabel(input) {
    const label = this.tokenValueTargets.find(
      (el) => el.dataset.token === input.dataset.token,
    )
    if (label) label.textContent = input.value.toUpperCase()
  }

  markSwatch(key) {
    this.swatchTargets.forEach((swatch) => {
      swatch.classList.toggle("ring-2", swatch.dataset.key === key)
    })
  }

  // ===== Layout =====

  populateLayouts() {
    const select = this.layoutSelectTarget
    select.innerHTML = ""
    LAYOUT_CATEGORIES.forEach((category) => {
      const group = document.createElement("optgroup")
      group.label = category.name
      category.layouts.forEach((layout) => {
        const option = document.createElement("option")
        option.value = layout.id
        option.textContent = layout.name
        group.appendChild(option)
      })
      select.appendChild(group)
    })
    select.value = DEFAULT_LAYOUT_ID
  }

  get layout() {
    return layoutById(this.layoutSelectTarget.value)
  }

  layoutChanged() {
    this.resizeFrame()
    this.updateSummary()
  }

  resizeFrame() {
    const layout = this.layout
    const { width, height } = fitFrame(this.stageTarget, layout.aspect)
    this.frameTarget.style.width = `${width}px`
    this.frameTarget.style.height = `${height}px`
    this.layoutDimsTarget.textContent = layout.dimensionsLabel
    this.previewMap?.resize()
    this.redrawOverlay()

    const isPaper = layout.kind === "paper"
    this.dpiFieldTarget.classList.toggle("invisible", !isPaper)
    const pdfOption = this.formatTarget.querySelector('option[value="pdf"]')
    pdfOption.disabled = !isPaper
    if (!isPaper && this.formatTarget.value === "pdf")
      this.formatTarget.value = "png"
  }

  // ===== Text =====

  populateFonts() {
    const select = this.fontSelectTarget
    select.innerHTML = ""
    POSTER_FONTS.forEach((font) => {
      const option = document.createElement("option")
      option.value = font.key
      option.textContent = font.label
      option.style.fontFamily = `"${font.family}", sans-serif`
      select.appendChild(option)
    })
    select.value = DEFAULT_FONT_KEY
  }

  async loadFonts() {
    await Promise.allSettled(
      POSTER_FONTS.map((font) => ensurePosterFont(font.key, this.fontsValue)),
    )
  }

  get fontFamily() {
    return `"${fontByKey(this.fontSelectTarget.value).family}", sans-serif`
  }

  textChanged() {
    const enabled = this.textToggleTarget.checked
    ;[
      this.titleInputTarget,
      this.subtitleInputTarget,
      this.coordsToggleTarget,
      this.fontSelectTarget,
    ].forEach((el) => {
      el.disabled = !enabled
    })
    this.redrawOverlay()
  }

  async fontChanged() {
    await ensurePosterFont(this.fontSelectTarget.value, this.fontsValue)
    this.redrawOverlay()
  }

  posterText() {
    if (!this.textToggleTarget.checked)
      return { title: "", subtitle: "", coords: "" }
    return {
      title: this.titleInputTarget.value.trim(),
      subtitle: this.subtitleInputTarget.value.trim(),
      coords: this.coordsToggleTarget.checked
        ? formatCoords(this.previewMap?.getCenter())
        : "",
    }
  }

  dateRangeLabel() {
    const controller = this.mapController
    if (!controller?.startDateValue || !controller?.endDateValue) return ""
    const options = { day: "numeric", month: "short", year: "numeric" }
    const start = new Date(controller.startDateValue)
    const end = new Date(controller.endDateValue)
    return `${start.toLocaleDateString("en-GB", options)} – ${end.toLocaleDateString("en-GB", options)}`
  }

  // ===== Layers =====

  layersChanged() {
    this.hidden = new Set()
    this.element.querySelectorAll("[data-layer-category]").forEach((toggle) => {
      if (!toggle.checked) this.hidden.add(toggle.dataset.layerCategory)
    })
    this.trackOpacityLabelTarget.textContent = `${this.trackOpacityTarget.value}%`
    this.scheduleRestyle()
  }

  trackOpacityValue() {
    return Number.parseInt(this.trackOpacityTarget.value, 10) / 100
  }

  // ===== Date range =====

  seedDateInputs() {
    const controller = this.mapController
    if (!controller?.startDateValue) return
    this.dateStartTarget.value = toLocalInput(
      new Date(controller.startDateValue),
    )
    this.dateEndTarget.value = toLocalInput(new Date(controller.endDateValue))
  }

  // SPA date change, same as the timeline: dispatch the shared event so the
  // main map reloads its layers in place — the studio never closes. The URL
  // is pushed for browser-state consistency.
  async applyDates() {
    const start = this.dateStartTarget.value
    const end = this.dateEndTarget.value
    if (!start || !end || !this.mapController) return

    const params = new URLSearchParams(window.location.search)
    params.set("start_at", start)
    params.set("end_at", end)
    window.history.pushState({}, "", `/map/v2?${params.toString()}`)

    const subtitleWasAuto =
      this.subtitleInputTarget.value === this.dateRangeLabel()
    this.setStatus("Loading tracks for the new range…")
    document.dispatchEvent(
      new CustomEvent("timeline-feed:date-navigated", {
        detail: { startAt: start, endAt: end },
      }),
    )
    await this.waitForTrackReload()

    if (subtitleWasAuto) this.subtitleInputTarget.value = this.dateRangeLabel()
    this.previewMap?.setStyle(this.posterStyle())
    this.recenter()
    this.syncSaveAvailability()
    this.setStatus("")
  }

  // The reload replaces the layer data objects; wait for the identity to
  // change and then stay stable for two polls (progressive loading lands
  // in several passes), capped at ~16s.
  async waitForTrackReload() {
    const layerManager = this.mapController?.layerManager
    const snapshot = () => ({
      routes: layerManager?.getLayer("routes")?.data,
      tracks: layerManager?.getLayer("tracks")?.data,
    })
    const before = snapshot()
    let changed = false
    let stable = 0
    let last = before
    for (let i = 0; i < 40; i++) {
      await new Promise((resolve) => setTimeout(resolve, 400))
      const current = snapshot()
      if (current.routes !== before.routes || current.tracks !== before.tracks)
        changed = true
      if (changed) {
        stable =
          current.routes === last.routes && current.tracks === last.tracks
            ? stable + 1
            : 0
        if (stable >= 2) return
      }
      last = current
    }
  }

  presetRange(event) {
    const now = new Date()
    const start = new Date(now)
    switch (event.currentTarget.dataset.range) {
      case "today":
        start.setHours(0, 0, 0, 0)
        break
      case "week":
        start.setDate(start.getDate() - 7)
        break
      case "month":
        start.setMonth(start.getMonth() - 1)
        break
    }
    this.dateStartTarget.value = toLocalInput(start)
    this.dateEndTarget.value = toLocalInput(now)
    this.applyDates()
  }

  // ===== Map interaction =====

  recenter() {
    const bounds = trackBounds(this.trackGeojson) ?? this.mainMapBounds()
    if (bounds) this.previewMap?.fitBounds(bounds, { padding: 24 })
  }

  // ===== Preview overlay =====

  redrawOverlay() {
    if (!this.hasOverlayTarget) return
    const canvas = this.overlayTarget
    const dpr = window.devicePixelRatio || 1
    canvas.width = Math.round(this.frameTarget.clientWidth * dpr)
    canvas.height = Math.round(this.frameTarget.clientHeight * dpr)
    canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height)
    drawOverlay(canvas, {
      theme: this.resolvedTheme,
      ...this.posterText(),
      font: this.fontFamily,
    })
  }

  // ===== Export =====

  async download() {
    if (this.busy || !this.previewMap) return
    try {
      this.setBusy(true)
      const layout = this.layout
      const dpi = Number.parseInt(this.dpiTarget.value, 10)
      const geometry = resolveLayoutGeometry(layout, dpi)
      this.setStatus(`Rendering ${geometry.width} × ${geometry.height}px…`)

      const mapBounds = this.previewMap.getBounds()
      const { blob, extension } = await exportPoster({
        style: this.posterStyle(),
        bounds: [
          [mapBounds.getWest(), mapBounds.getSouth()],
          [mapBounds.getEast(), mapBounds.getNorth()],
        ],
        layout,
        dpi,
        format: this.formatTarget.value,
        theme: this.resolvedTheme,
        text: this.posterText(),
        font: this.fontFamily,
        cssSize: {
          width: this.frameTarget.clientWidth,
          height: this.frameTarget.clientHeight,
        },
      })
      downloadBlob(
        blob,
        studioFilename(this.titleInputTarget.value, layout, extension),
      )
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

  // Server-side render through the sidecar: fills the hidden posters form
  // from the studio state and submits via Turbo. The sidecar renders its
  // classic 3:4 print poster around the studio's center; the result lands
  // in Recent posters via the gallery broadcast.
  saveToGallery() {
    if (!this.previewMap || this.saveButtonTarget.disabled) return
    const center = this.previewMap.getCenter()
    const distance = this.sidecarDistance()

    this.saveNameTarget.value =
      this.titleInputTarget.value.trim() || "My Poster"
    this.saveThemeTarget.value = this.themeBase || "blueprint"
    this.saveLatTarget.value = center.lat
    this.saveLonTarget.value = center.lng
    this.saveDistanceTarget.value = distance
    this.saveStartAtTarget.value = this.mapController?.startDateValue || ""
    this.saveEndAtTarget.value = this.mapController?.endDateValue || ""
    this.saveSourceTarget.value = this.trackSource
    this.saveOpacityTarget.value = this.trackOpacityTarget.value
    this.saveFormTarget.requestSubmit()
    this.setStatus("Queued — rendering server-side into Recent posters…")
  }

  sidecarDistance() {
    const bounds = this.previewMap.getBounds()
    const heightMeters =
      (bounds.getNorth() - bounds.getSouth()) * METERS_PER_DEGREE
    const [min, max] = SIDECAR_DISTANCE_RANGE
    return Math.round(
      Math.min(max, Math.max(min, heightMeters * SIDECAR_DISTANCE_FACTOR)),
    )
  }

  // The server refuses renders without track data in the frame — mirror
  // both guards here so Save to gallery can't queue a doomed poster.
  syncSaveAvailability() {
    if (!this.hasSaveButtonTarget || !this.previewMap) return
    const coords = collectCoords(this.trackGeojson)
    let reason = null
    if (coords.length === 0) {
      reason =
        "No location data in this date range — pick a range with tracks in the date bar above."
    } else if (!this.frameCoversTrack(coords)) {
      reason =
        "No tracks inside the frame — move or zoom the map over your route to save to the gallery."
    }
    this.saveButtonTarget.disabled = Boolean(reason)
    this.saveNoticeTarget.textContent = reason || ""
    this.saveNoticeTarget.classList.toggle("hidden", !reason)
  }

  // Mirrors the server's track_intersects_area? box: ±distance/3 latitude,
  // ±distance/4 longitude around the frame center.
  frameCoversTrack(coords) {
    const center = this.previewMap.getCenter()
    const distance = this.sidecarDistance()
    const latDelta = distance / 3 / METERS_PER_DEGREE
    const cosLat = Math.max(Math.cos((center.lat * Math.PI) / 180), 0.01)
    const lonDelta = distance / 4 / (METERS_PER_DEGREE * cosLat)
    return coords.some(
      ([lng, lat]) =>
        lng >= center.lng - lonDelta &&
        lng <= center.lng + lonDelta &&
        lat >= center.lat - latDelta &&
        lat <= center.lat + latDelta,
    )
  }

  updateSummary() {
    const layout = this.layout
    const dpi = Number.parseInt(this.dpiTarget.value, 10)
    const geometry = resolveLayoutGeometry(layout, dpi)
    const lines = [
      `${layout.name} — ${layout.dimensionsLabel}`,
      `Theme: ${this.themeName || "—"}`,
      `Export: ${geometry.width} × ${geometry.height}px${
        layout.kind === "paper" ? ` @ ${geometry.effectiveDpi} dpi` : ""
      }`,
    ]
    this.summaryTarget.textContent = lines.join(" · ")
  }

  // ===== Data plumbing =====

  get trackSource() {
    const layerManager = this.mapController?.layerManager
    if (layerManager?.getLayer("routes")?.data?.features?.length)
      return "routes"
    if (layerManager?.getLayer("tracks")?.data?.features?.length)
      return "tracks"
    return "routes"
  }

  get trackGeojson() {
    return (
      this.mapController?.layerManager?.getLayer(this.trackSource)?.data ?? {
        type: "FeatureCollection",
        features: [],
      }
    )
  }

  mainMapBounds() {
    const bounds = this.mapController?.map?.getBounds()
    if (!bounds) return null
    return [
      [bounds.getWest(), bounds.getSouth()],
      [bounds.getEast(), bounds.getNorth()],
    ]
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

  setStatus(text) {
    this.statusTarget.textContent = text
  }

  setBusy(value) {
    this.busy = value
    this.downloadButtonTarget.disabled = value
  }
}
