import { Controller } from "@hotwired/stimulus"

// Shared "name your video" modal. Trigger buttons in the same DOM scope
// (day, track-info) supply track-id or date via Stimulus params; this
// controller populates the form and opens the <dialog>.
export default class extends Controller {
  static targets = ["dialog", "trackId", "date", "name", "title"]

  open({ params }) {
    const trackId = params.trackId || ""
    const date = params.date || ""

    this.trackIdTarget.value = trackId
    this.dateTarget.value = date
    this.nameTarget.value = ""

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = date
        ? `Generate video for ${date}`
        : "Generate replay video"
    }

    this.dialogTarget.showModal()
    setTimeout(() => this.nameTarget.focus(), 50)
  }

  closeOnSuccess(event) {
    if (event.detail?.success) this.dialogTarget.close()
  }

  close() {
    this.dialogTarget.close()
  }
}
