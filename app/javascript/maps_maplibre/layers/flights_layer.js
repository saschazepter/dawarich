import maplibregl from "maplibre-gl"
import { BaseLayer } from "./base_layer"

/**
 * Flights layer: AirTrail flights drawn as arcs between departure and arrival
 * airports. Styling respects the saved MapLibre style (light/dark) passed in
 * via options, not the DOM dark-mode class.
 */
export class FlightsLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "flights", ...options })
    this.style = options.style || "light"
    this.popup = new maplibregl.Popup({
      closeButton: true,
      closeOnClick: true,
      className: "flights-popup",
    })
    this._onClick = this._onClick.bind(this)
  }

  lineColor() {
    return this.style === "dark" ? "#f59e0b" : "#b45309"
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || { type: "FeatureCollection", features: [] },
    }
  }

  getLayerConfigs() {
    return [
      {
        id: this.id,
        type: "line",
        source: this.sourceId,
        layout: { "line-join": "round", "line-cap": "round" },
        paint: {
          "line-color": this.lineColor(),
          "line-width": 2,
          "line-opacity": 0.8,
          "line-dasharray": [2, 1],
        },
      },
    ]
  }

  add(data) {
    super.add(data)
    this.map.on("click", this.id, this._onClick)
    this.map.on("mouseenter", this.id, this._setPointer)
    this.map.on("mouseleave", this.id, this._unsetPointer)
  }

  remove() {
    this.map.off("click", this.id, this._onClick)
    this.map.off("mouseenter", this.id, this._setPointer)
    this.map.off("mouseleave", this.id, this._unsetPointer)
    super.remove()
  }

  _setPointer = () => {
    this.map.getCanvas().style.cursor = "pointer"
  }

  _unsetPointer = () => {
    this.map.getCanvas().style.cursor = ""
  }

  _onClick(event) {
    const feature = event.features?.[0]
    if (!feature) return

    const p = feature.properties || {}
    const route = [p.from_code, p.to_code].filter(Boolean).join(" → ")
    const airline = p.airline_name ? `<div>${p.airline_name}</div>` : ""
    const number = p.flight_number ? ` ${p.flight_number}` : ""
    const date = p.flight_date ? `<div>${p.flight_date}</div>` : ""
    const seat = p.seat ? `<div>Seat: ${p.seat}</div>` : ""

    const html = `
      <div class="text-sm">
        <strong>${route}${number}</strong>
        ${airline}${date}${seat}
      </div>
    `

    this.popup.setLngLat(event.lngLat).setHTML(html).addTo(this.map)
  }
}
