import { Controller } from "@hotwired/stimulus"

// Replaces the legacy radio-list picker (which reads from `place_visits`)
// with live Photon suggestions fetched from /api/v1/visits/:id/possible_places.
//
// Selection flow:
// - Existing place (has integer id): submits PATCH /visits/:id with place_id
//   (existing path, no change)
// - Photon-only candidate (id=null): POSTs /visits/:id/select_place with the
//   full Photon payload, which calls Visits::SelectPlace to materialize the
//   Place row + assign it to the visit
//
// TODO(next pass): wire targets, fetch logic, and submission handlers
export default class extends Controller {
  static values = {
    visitId: Number,
    apiKey: String,
    possiblePlacesUrl: String,
    selectPlaceUrl: String
  }

  static targets = ["list", "submit"]

  connect() {
    // TODO: fetch this.possiblePlacesUrlValue with this.apiKeyValue
    //       and render <li> entries into this.listTarget
  }

  selectExisting(_event) {
    // TODO: build a PATCH form_with place_id and requestSubmit() via Turbo
  }

  selectPhoton(_event) {
    // TODO: POST to this.selectPlaceUrlValue with the chosen radio's
    //       data-photon-* attributes as the photon: payload
  }
}
