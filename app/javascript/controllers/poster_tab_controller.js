import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "lat",
    "lon",
    "distance",
    "startAt",
    "endAt",
    "source",
    "areaLabel",
    "submit",
    "emptyNotice",
    "outOfAreaNotice",
  ]

  static MAX_DISTANCE = 20000
  static MIN_DISTANCE = 500
  static METERS_PER_DEGREE = 111320
  // The sidecar renders ±distance/3 vertically, ±distance/4 horizontally
  // (compensated_dist + portrait crop in maptoposter) — hence factor 3 and 3:4.
  static DIST_FACTOR = 3
  static LON_DIST_FACTOR = 4
  static POSTER_ASPECT = 0.75
  static FRAME_PADDING = 16

  connect() {
    this.active = false
    this.boundTabChanged = (event) => this.tabChanged(event)
    this.boundPanelClosed = () => this.deactivate()
    this.boundSyncFrame = () => this.syncFrame()
    this.boundSyncEmptyState = () => this.syncEmptyState()
    this.boundTurboLoad = () => this.reattachToMap()
    document.addEventListener("map-panel:tab-changed", this.boundTabChanged)
    document.addEventListener("map-panel:closed", this.boundPanelClosed)
    document.addEventListener("turbo:load", this.boundTurboLoad)
  }

  disconnect() {
    this.deactivate()
    document.removeEventListener("map-panel:tab-changed", this.boundTabChanged)
    document.removeEventListener("map-panel:closed", this.boundPanelClosed)
    document.removeEventListener("turbo:load", this.boundTurboLoad)
  }

  // The settings panel is data-turbo-permanent: it survives date navigation
  // while the map container (and MapLibre instance) is rebuilt, so map
  // listeners die and `this.active` may reset if Stimulus reconnects during
  // the element transfer. The tab's DOM active class is the source of truth.
  reattachToMap() {
    this.active = false
    if (this.tabSelected) this.activate()
  }

  get tabSelected() {
    return Boolean(
      this.element
        .closest('[data-tab-content="poster"]')
        ?.classList.contains("active"),
    )
  }

  tabChanged(event) {
    if (event.detail?.tab === "poster") {
      this.activate()
    } else {
      this.deactivate()
    }
  }

  // Hidden fields can go stale when map listeners die (e.g. a long-lived tab
  // running pre-fix code) — re-read the live map right before Turbo
  // serializes the form so the submitted values always match the frame.
  prepareSubmit() {
    this.syncFrame()
  }

  activate() {
    if (this.active) return
    const map = this.map
    if (!map) {
      this.scheduleActivationRetry()
      return
    }

    this.active = true
    map.on("moveend", this.boundSyncFrame)
    map.on("resize", this.boundSyncFrame)
    map.on("idle", this.boundSyncEmptyState)
    this.frameElement?.classList.remove("hidden")
    this.crosshairElement?.classList.remove("hidden")
    this.syncFrame()
  }

  scheduleActivationRetry() {
    if (this.activationTimer) return
    this.activationTimer = setTimeout(() => {
      this.activationTimer = null
      this.activate()
    }, 250)
  }

  deactivate() {
    if (this.activationTimer) {
      clearTimeout(this.activationTimer)
      this.activationTimer = null
    }
    if (!this.active) return

    this.active = false
    const map = this.map
    if (map) {
      map.off("moveend", this.boundSyncFrame)
      map.off("resize", this.boundSyncFrame)
      map.off("idle", this.boundSyncEmptyState)
    }
    this.frameElement?.classList.add("hidden")
    this.crosshairElement?.classList.add("hidden")
  }

  syncFrame() {
    const map = this.map
    if (!map) return

    const {
      MAX_DISTANCE,
      MIN_DISTANCE,
      METERS_PER_DEGREE,
      DIST_FACTOR,
      POSTER_ASPECT,
      FRAME_PADDING,
    } = this.constructor
    const container = map.getContainer()
    const bounds = map.getBounds()
    const metersPerPixel =
      ((bounds.getNorth() - bounds.getSouth()) * METERS_PER_DEGREE) /
      container.clientHeight

    const maxFrameHeightPx = Math.min(
      container.clientHeight - FRAME_PADDING * 2,
      (container.clientWidth - FRAME_PADDING * 2) / POSTER_ASPECT,
    )
    const desired = Math.round(
      DIST_FACTOR * (maxFrameHeightPx / 2) * metersPerPixel,
    )
    const clamped = Math.min(Math.max(desired, MIN_DISTANCE), MAX_DISTANCE)

    const center = map.getCenter()
    this.latTarget.value = center.lat.toFixed(6)
    this.lonTarget.value = center.lng.toFixed(6)
    this.distanceTarget.value = clamped
    this.syncRange()
    this.syncSource()
    this.syncEmptyState()

    const posterHeightMeters = (2 * clamped) / DIST_FACTOR
    const frameHeightPx = posterHeightMeters / metersPerPixel
    const frameWidthPx = frameHeightPx * POSTER_ASPECT

    const frame = this.frameElement
    if (frame) {
      frame.style.height = `${Math.round(frameHeightPx)}px`
      frame.style.width = `${Math.round(frameWidthPx)}px`
    }

    if (this.hasAreaLabelTarget) {
      const heightKm = (posterHeightMeters / 1000).toFixed(1)
      const widthKm = ((posterHeightMeters * POSTER_ASPECT) / 1000).toFixed(1)
      this.areaLabelTarget.textContent =
        desired > MAX_DISTANCE
          ? `Poster area: ${widthKm} × ${heightKm} km (max — zoom in for street detail)`
          : `Poster area: ${widthKm} × ${heightKm} km`
    }
  }

  syncRange() {
    const controller = this.mapController
    if (!controller) return
    this.startAtTarget.value = controller.startDateValue
    this.endAtTarget.value = controller.endDateValue
  }

  syncSource() {
    const layerManager = this.mapController?.layerManager
    if (!layerManager) {
      this.sourceTarget.value = "routes"
      return
    }
    const routesVisible = layerManager.getLayer("routes")?.visible
    const tracksVisible = layerManager.getLayer("tracks")?.visible
    this.sourceTarget.value =
      !routesVisible && tracksVisible ? "tracks" : "routes"
  }

  syncEmptyState() {
    const hasData = this.sourceHasData()
    const inFrame = hasData ? this.trackInFrame() : false

    if (this.hasSubmitTarget) {
      const themesMissing = this.submitTarget.dataset.themesMissing === "true"
      this.submitTarget.disabled = themesMissing || !hasData || !inFrame
    }
    if (this.hasEmptyNoticeTarget) {
      this.emptyNoticeTarget.classList.toggle("hidden", hasData)
    }
    if (this.hasOutOfAreaNoticeTarget) {
      this.outOfAreaNoticeTarget.classList.toggle("hidden", !hasData || inFrame)
    }
  }

  sourceHasData() {
    const features = this.sourceFeatures()
    if (!features) return true
    return features.length > 0
  }

  sourceFeatures() {
    const layerManager = this.mapController?.layerManager
    if (!layerManager) return null
    const layerId = this.sourceTarget.value === "tracks" ? "tracks" : "routes"
    return layerManager.getLayer(layerId)?.data?.features ?? null
  }

  // Mirrors the server's track_intersects_area? box (±distance/3 lat,
  // ±distance/4 lon around the centre) so the client and server agree on
  // whether the track passes through the poster frame.
  trackInFrame() {
    const features = this.sourceFeatures()
    if (!features || features.length === 0) return true

    const lat = parseFloat(this.latTarget.value)
    const lon = parseFloat(this.lonTarget.value)
    const distance = parseFloat(this.distanceTarget.value)
    if (![lat, lon, distance].every(Number.isFinite)) return true

    const { METERS_PER_DEGREE, DIST_FACTOR, LON_DIST_FACTOR } = this.constructor
    const latDelta = distance / DIST_FACTOR / METERS_PER_DEGREE
    const cosLat = Math.min(
      Math.max(Math.abs(Math.cos((lat * Math.PI) / 180)), 0.01),
      1,
    )
    const lonDelta = distance / LON_DIST_FACTOR / (METERS_PER_DEGREE * cosLat)
    const box = {
      latMin: lat - latDelta,
      latMax: lat + latDelta,
      lonMin: lon - lonDelta,
      lonMax: lon + lonDelta,
    }

    return features.some((feature) =>
      this.geometryTouchesBox(feature?.geometry, box),
    )
  }

  geometryTouchesBox(geometry, box) {
    if (!geometry) return false
    const { type, coordinates } = geometry
    let lines
    if (type === "MultiLineString") lines = coordinates
    else if (type === "LineString") lines = [coordinates]
    else if (type === "MultiPoint") lines = [coordinates]
    else if (type === "Point") lines = [[coordinates]]
    else return false

    for (const line of lines) {
      for (const point of line) {
        const [pointLon, pointLat] = point
        if (
          pointLat >= box.latMin &&
          pointLat <= box.latMax &&
          pointLon >= box.lonMin &&
          pointLon <= box.lonMax
        ) {
          return true
        }
      }
    }
    return false
  }

  get mapController() {
    const container = document.getElementById("maps-maplibre-container")
    if (!container) return null
    return this.application.getControllerForElementAndIdentifier(
      container,
      "maps--maplibre",
    )
  }

  get map() {
    return this.mapController?.map
  }

  get frameElement() {
    return document.getElementById("poster-frame")
  }

  get crosshairElement() {
    return document.getElementById("poster-crosshair")
  }
}
