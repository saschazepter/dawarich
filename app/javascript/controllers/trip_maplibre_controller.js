import { Controller } from "@hotwired/stimulus"
import { MapInitializer } from "controllers/maps/maplibre/map_initializer"
import maplibregl from "maplibre-gl"
import { DayRoutesLayer } from "maps_maplibre/layers/day_routes_layer"
import { PhotosLayer } from "maps_maplibre/layers/photos_layer"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"
import { ReplayPanel } from "maps_maplibre/managers/replay_panel"
import { ApiClient } from "maps_maplibre/services/api_client"
import { featureToPhoto } from "maps_maplibre/utils/feature_to_photo"

/**
 * Trip MapLibre Controller
 * Renders a MapLibre map for the trip show page with day-colored routes,
 * an accordion-based day navigator, photos overlay, and trip replay.
 */
export default class extends Controller {
  static targets = [
    "map",
    "daysAccordion",
    "expandAllBtn",
    "loadingIndicator",
    // Photos button
    "photosToggleBtn",
    // Replay toggle button
    "replayToggleBtn",
    // Replay panel
    "replayPanel",
    "replayScrubber",
    "replayScrubberTrack",
    "replayDensityContainer",
    "replayDayDisplay",
    "replayDayCount",
    "replayTimeDisplay",
    "replayDataIndicator",
    "replayCycleControls",
    "replayPointCounter",
    "replayPrevDayButton",
    "replayNextDayButton",
    "replayPlayButton",
    "replayPlayIcon",
    "replayPauseIcon",
    "replaySpeedSlider",
    "replaySpeedLabel",
    "replaySpeedDisplay",
  ]

  static values = {
    apiKey: String,
    timezone: String,
    startedAt: String,
    endedAt: String,
    tripId: Number,
    pathData: String,
    mapStyle: { type: String, default: "light" },
  }

  async connect() {
    this.pointsByDay = {}
    this.selectedDay = null
    this.dayRoutesLayer = null
    this.photosLayer = null
    this.photosGeoJSON = null
    this.photosActive = false
    this.mapInitializing = false
    this.overviewSourceId = "trip-overview-source"
    this.overviewLayerId = "trip-overview-layer"

    // Replay (managed by ReplayPanel)
    this.allPoints = []
    this.replayPanel = null

    if (this.hasMapTarget) {
      await this.initializeMap()
    }
  }

  disconnect() {
    this.replayPanel?.destroy()
    if (this.photosLayer) {
      this.photosLayer.remove()
      this.photosLayer = null
    }
    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.remove()
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
    this.mapInitializing = false
  }

  async mapTargetConnected() {
    if (!this.map && !this.mapInitializing) {
      await this.initializeMap()
    }
  }

  async initializeMap() {
    if (!this.hasMapTarget || this.mapInitializing) return
    this.mapInitializing = true

    this.map = await MapInitializer.initialize(this.mapTarget, {
      mapStyle: this.mapStyleValue,
      center: [0, 0],
      zoom: 2,
      showControls: true,
    })

    this.map.on("load", async () => {
      this.showPathOverview()
      await this.fetchAndProcessPoints()
    })
  }

  getPathData() {
    const raw =
      this.pathDataValue ||
      (this.hasMapTarget && this.mapTarget.dataset.pathCoordinates)
    return raw || null
  }

  showPathOverview() {
    const pathData = this.getPathData()
    if (!pathData) return

    try {
      const coordinates = JSON.parse(pathData)
      if (!coordinates.length) return

      if (this.map.getSource(this.overviewSourceId)) return

      const geojson = {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: coordinates,
        },
      }

      this.map.addSource(this.overviewSourceId, {
        type: "geojson",
        data: geojson,
      })

      this.map.addLayer({
        id: this.overviewLayerId,
        type: "line",
        source: this.overviewSourceId,
        layout: {
          "line-join": "round",
          "line-cap": "round",
        },
        paint: {
          "line-color": "#6366F1",
          "line-width": 3,
          "line-opacity": 0.8,
        },
      })

      const bounds = new maplibregl.LngLatBounds()
      for (const coord of coordinates) {
        bounds.extend(coord)
      }
      if (!bounds.isEmpty()) {
        this.map.fitBounds(bounds, { padding: 50, maxZoom: 15 })
      }
    } catch (e) {
      console.error("[TripMapLibre] Error showing path overview:", e)
    }
  }

  async fetchAndProcessPoints() {
    const apiClient = new ApiClient(this.apiKeyValue)

    try {
      this.showLoading(true)

      const { points: allPoints } = await apiClient.fetchAllPoints({
        start_at: this.startedAtValue,
        end_at: this.endedAtValue,
      })

      if (!allPoints?.length) {
        this.showLoading(false)
        return
      }

      // Use ReplayManager for canonical day grouping
      const grouper = new ReplayManager({ timezone: this.timezoneValue })
      grouper.setPoints(allPoints)
      this.pointsByDay = {}
      for (const dayKey of grouper.availableDays) {
        this.pointsByDay[dayKey] = grouper.getPointsForDay(dayKey)
      }
      const dayKeys = Object.keys(this.pointsByDay).sort()

      if (!dayKeys.length) {
        this.showLoading(false)
        return
      }

      this.removeOverviewLine()

      this.dayRoutesLayer = new DayRoutesLayer(this.map)
      this.dayRoutesLayer.addDayRoutes(this.pointsByDay)

      this.applyDayColors(dayKeys)

      this.dayRoutesLayer.setupInteractions({
        onDayClick: (dayKey) => this.selectDayFromMap(dayKey),
      })

      const fullBounds = this.dayRoutesLayer.getFullBounds()
      if (fullBounds) {
        this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
      }

      // Store all points for replay use
      this.allPoints = allPoints

      // The replay panel may have been opened before points finished loading
      if (
        this.hasReplayPanelTarget &&
        !this.replayPanelTarget.classList.contains("hidden")
      ) {
        if (this.replayPanel) {
          this.replayPanel.allPoints = this.allPoints
          this.replayPanel.init()
        }
      }

      this.showLoading(false)
    } catch (e) {
      console.error("[TripMapLibre] Error fetching points:", e)
      this.showLoading(false)
    }
  }

  applyDayColors(dayKeys) {
    if (!this.hasDaysAccordionTarget) return

    for (const dayKey of dayKeys) {
      const color = this.dayRoutesLayer.getDayColor(dayKey)
      const dot = this.daysAccordionTarget.querySelector(
        `[data-day-dot="${dayKey}"]`,
      )
      if (dot && color) {
        dot.style.backgroundColor = color
      }
    }
  }

  selectDayFromMap(dayKey) {
    if (!this.hasDaysAccordionTarget) return

    const allDetails = this.daysAccordionTarget.querySelectorAll(
      "details[data-day-key]",
    )
    const target = this.daysAccordionTarget.querySelector(
      `details[data-day-key="${dayKey}"]`,
    )
    if (!target) return

    for (const d of allDetails) {
      if (d !== target) {
        d.removeAttribute("open")
      }
    }
    target.setAttribute("open", "")

    this.selectedDay = dayKey

    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.selectDay(dayKey)

      const dayBounds = this.dayRoutesLayer.getDayBounds(dayKey)
      if (dayBounds) {
        this.map.fitBounds(dayBounds, { padding: 50, maxZoom: 15 })
      }
    }

    target.scrollIntoView({ behavior: "smooth", block: "nearest" })

    this.replayPanel?.syncToDay(dayKey)
  }

  toggleDay(event) {
    event.preventDefault()

    const summary = event.currentTarget
    const details = summary.closest("details")
    const dayKey = summary.dataset.tripMaplibreDayKeyParam
    if (!details || !dayKey) return

    if (details.open) {
      details.removeAttribute("open")
      this.selectedDay = null

      if (this.dayRoutesLayer) {
        this.dayRoutesLayer.selectAllDays()

        const fullBounds = this.dayRoutesLayer.getFullBounds()
        if (fullBounds) {
          this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
        }
      }
    } else {
      const allDetails = this.daysAccordionTarget.querySelectorAll(
        "details[data-day-key]",
      )
      for (const d of allDetails) {
        if (d !== details) {
          d.removeAttribute("open")
        }
      }
      details.setAttribute("open", "")

      this.selectedDay = dayKey

      if (this.dayRoutesLayer) {
        this.dayRoutesLayer.selectDay(dayKey)

        const dayBounds = this.dayRoutesLayer.getDayBounds(dayKey)
        if (dayBounds) {
          this.map.fitBounds(dayBounds, { padding: 50, maxZoom: 15 })
        }
      }

      this.replayPanel?.syncToDay(dayKey)
    }
  }

  expandAllDays() {
    if (!this.hasDaysAccordionTarget) return

    const allDetails = this.daysAccordionTarget.querySelectorAll(
      "details[data-day-key]",
    )
    const allOpen = Array.from(allDetails).every((d) => d.hasAttribute("open"))

    if (allOpen) {
      for (const d of allDetails) {
        d.removeAttribute("open")
      }
      if (this.hasExpandAllBtnTarget) {
        this.expandAllBtnTarget.textContent = "Show all days"
      }
    } else {
      for (const d of allDetails) {
        d.setAttribute("open", "")
      }
      if (this.hasExpandAllBtnTarget) {
        this.expandAllBtnTarget.textContent = "Collapse all days"
      }
    }

    this.selectedDay = null

    if (this.dayRoutesLayer) {
      this.dayRoutesLayer.selectAllDays()

      const fullBounds = this.dayRoutesLayer.getFullBounds()
      if (fullBounds) {
        this.map.fitBounds(fullBounds, { padding: 50, maxZoom: 15 })
      }
    }
  }

  removeOverviewLine() {
    if (this.map.getLayer(this.overviewLayerId)) {
      this.map.removeLayer(this.overviewLayerId)
    }
    if (this.map.getSource(this.overviewSourceId)) {
      this.map.removeSource(this.overviewSourceId)
    }
  }

  showLoading(show) {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.toggle("hidden", !show)
    }
  }

  // ===== Photos layer toggle (button-based) =====

  async togglePhotos() {
    this.photosActive = !this.photosActive

    if (!this.photosActive) {
      if (this.photosLayer) {
        this.photosLayer.remove()
        this.photosLayer = null
      }
      this._setButtonActive(this.photosToggleBtnTarget, false)
      return
    }

    if (!this.photosGeoJSON) {
      const apiClient = new ApiClient(this.apiKeyValue)
      try {
        const photos = await apiClient.fetchPhotos({
          start_at: this.startedAtValue,
          end_at: this.endedAtValue,
        })
        this.photosGeoJSON = this.photosToGeoJSON(photos)
      } catch (e) {
        console.error("[TripMapLibre] Error fetching photos:", e)
        this.photosActive = false
        return
      }
    }

    if (this.photosGeoJSON.features.length === 0) {
      this.photosActive = false
      return
    }

    this.photosLayer = new PhotosLayer(this.map)
    this.photosLayer.add(this.photosGeoJSON)
    this._setButtonActive(this.photosToggleBtnTarget, true)
  }

  photosToGeoJSON(photos) {
    return {
      type: "FeatureCollection",
      features: photos.map((photo) => {
        const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${this.apiKeyValue}&source=${photo.source}`
        return {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [photo.longitude, photo.latitude],
          },
          properties: {
            id: photo.id,
            thumbnail_url: thumbnailUrl,
            taken_at: photo.capturedAt || photo.localDateTime,
            filename: photo.originalFileName,
            city: photo.city,
            state: photo.state,
            country: photo.country,
            type: photo.type,
            source: photo.source,
          },
        }
      }),
    }
  }

  // ===== Note form toggling =====

  showNoteForm(event) {
    this.toggleNoteVisibility(event.currentTarget.dataset.date, true)
  }

  hideNoteForm(event) {
    this.toggleNoteVisibility(event.currentTarget.dataset.date, false)
  }

  toggleNoteVisibility(date, showForm) {
    const display = this.element.querySelector(`[data-note-display="${date}"]`)
    const form = this.element.querySelector(`[data-note-form="${date}"]`)
    if (display) display.classList.toggle("hidden", showForm)
    if (form) form.classList.toggle("hidden", !showForm)
  }

  // ===== Replay (delegates to the reusable ReplayPanel) =====

  toggleReplay() {
    if (!this.hasReplayPanelTarget) return
    if (!this.replayPanel) {
      this.replayPanel = new ReplayPanel({
        controller: this,
        map: this.map,
        dayRoutesLayer: this.dayRoutesLayer,
        element: this.element,
        timezone: this.timezoneValue,
        allPoints: this.allPoints,
        getPhotos: () =>
          this.photosActive && this.photosGeoJSON
            ? this.photosGeoJSON.features.map(featureToPhoto)
            : [],
        onReplayPhotosActive: (active) => {
          if (!this.photosLayer) return
          if (active) {
            this.photosLayer.hide()
          } else {
            this.photosLayer.show()
          }
        },
      })
    }
    this.replayPanel.toggle()
  }

  replayScrubberHover(event) {
    this.replayPanel?.scrubberHover(event)
  }

  replayPrevDay() {
    this.replayPanel?.prevDay()
  }

  replayNextDay() {
    this.replayPanel?.nextDay()
  }

  replayCyclePrev() {
    this.replayPanel?.cyclePrev()
  }

  replayCycleNext() {
    this.replayPanel?.cycleNext()
  }

  replayTogglePlayback() {
    this.replayPanel?.togglePlayback()
  }

  replaySpeedChange(event) {
    this.replayPanel?.speedChange(event)
  }

  // --- Button active state helper ---

  _setButtonActive(button, active) {
    if (!button) return
    if (active) {
      button.classList.remove("btn-outline")
      button.classList.add("btn-active", "btn-primary")
    } else {
      button.classList.remove("btn-active", "btn-primary")
      button.classList.add("btn-outline")
    }
  }
}
