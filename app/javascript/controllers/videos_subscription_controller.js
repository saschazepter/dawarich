import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["tbody"]

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "VideosChannel" },
      { received: (data) => this.replaceRow(data) },
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  replaceRow(data) {
    if (!data?.id || !data.html) return
    const existing = document.getElementById(data.id)
    if (existing) {
      existing.outerHTML = data.html
      return
    }
    if (this.hasTbodyTarget) {
      const emptyRow = this.tbodyTarget.querySelector("[data-videos-empty]")
      if (emptyRow) emptyRow.remove()
      this.tbodyTarget.insertAdjacentHTML("afterbegin", data.html)
    }
  }
}
