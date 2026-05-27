import { Controller } from "@hotwired/stimulus"

// Map v2 Memories — "On this day, N time ago" reel.
// Bottom-floating reel of period chips (1mo, 6mo, 1y, 5y…). Tapping one
// opens a fullscreen viewer that flies the map to where the user was on
// that calendar day and auto-advances through the lookback ladder.
//
// The MapLibre controller listens for `memories:chapter-changed` events on
// the document to keep the visible map in sync with the open memory.
export default class extends Controller {
  static targets = [
    "reel",
    "viewer",
    "viewerFrame",
    "progressBar",
    "photo",
    "caption",
    "chapterTitle",
    "chapterDay",
    "reelItem",
    "mapArea",
  ]

  static values = {
    autoAdvanceMs: { type: Number, default: 7000 },
    activeIdx: { type: Number, default: 0 },
    chapters: Array,
  }

  static classes = ["mapBlurred"]

  connect() {
    this.boundKeydown = this.handleKeydown.bind(this)
    this.boundPause = this.pause.bind(this)
    this.boundResume = this.resume.bind(this)
  }

  disconnect() {
    this.clearAutoAdvance()
    document.removeEventListener("keydown", this.boundKeydown)
  }

  open(event) {
    const button = event.currentTarget
    const idx = Number.parseInt(button.dataset.idx, 10)
    if (Number.isNaN(idx)) return

    this.activeIdxValue = idx
    this.viewerTarget.classList.remove("hidden")
    this.viewerTarget.setAttribute("aria-hidden", "false")
    this.applyMapBlur(true)
    this.renderChapter()
    this.startAutoAdvance()
    document.addEventListener("keydown", this.boundKeydown)
    this.viewerFrameTarget.addEventListener("pointerdown", this.boundPause)
    this.viewerFrameTarget.addEventListener("pointerup", this.boundResume)
    this.viewerFrameTarget.addEventListener("pointerleave", this.boundResume)
  }

  close() {
    this.viewerTarget.classList.add("hidden")
    this.viewerTarget.setAttribute("aria-hidden", "true")
    this.applyMapBlur(false)
    this.clearAutoAdvance()
    document.removeEventListener("keydown", this.boundKeydown)
    this.viewerFrameTarget.removeEventListener("pointerdown", this.boundPause)
    this.viewerFrameTarget.removeEventListener("pointerup", this.boundResume)
    this.viewerFrameTarget.removeEventListener("pointerleave", this.boundResume)
  }

  next() {
    const total = this.chaptersValue.length
    if (this.activeIdxValue >= total - 1) {
      this.close()
      return
    }
    this.activeIdxValue += 1
    this.renderChapter()
    this.startAutoAdvance()
  }

  prev() {
    if (this.activeIdxValue <= 0) return
    this.activeIdxValue -= 1
    this.renderChapter()
    this.startAutoAdvance()
  }

  pause() {
    this.clearAutoAdvance()
  }

  resume() {
    this.startAutoAdvance()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    } else if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.prev()
    }
  }

  renderChapter() {
    const chapter = this.chaptersValue[this.activeIdxValue]
    if (!chapter) return

    const total = this.chaptersValue.length
    const idx = this.activeIdxValue
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.textContent = `Memory ${idx + 1} of ${total}`
    }
    if (this.hasChapterTitleTarget) {
      this.chapterTitleTarget.textContent = chapter.period_label
    }
    if (this.hasChapterDayTarget) {
      this.chapterDayTarget.textContent = chapter.date_long
    }
    if (this.hasCaptionTarget) {
      this.captionTarget.innerHTML = chapter.caption_html || ""
    }
    if (this.hasPhotoTarget) {
      this.renderMiniMap(chapter)
    }
    this.markActiveReelItem(idx)
    this.flyTo(idx)
  }

  renderMiniMap(chapter) {
    const lat = Number(chapter.lat)
    const lon = Number(chapter.lon)
    const code = (chapter.country || "·").toUpperCase()
    const city = chapter.name || ""
    this.photoTarget.innerHTML = `
      <svg viewBox="0 0 320 200" preserveAspectRatio="xMidYMid slice"
           xmlns="http://www.w3.org/2000/svg" class="memory-mini-map">
        <defs>
          <radialGradient id="memory-mm-grad" cx="50%" cy="50%" r="60%">
            <stop offset="0%" stop-color="oklch(var(--b2))"/>
            <stop offset="100%" stop-color="oklch(var(--b3))"/>
          </radialGradient>
        </defs>
        <rect width="320" height="200" fill="url(#memory-mm-grad)"/>
        <text x="160" y="40" text-anchor="middle"
              font-size="22" font-weight="700"
              fill="oklch(var(--bc) / 0.85)"
              font-family="-apple-system,system-ui,sans-serif">${city}</text>
        <text x="160" y="62" text-anchor="middle"
              font-size="11" font-weight="500" letter-spacing="2"
              fill="oklch(var(--bc) / 0.45)"
              font-family="-apple-system,system-ui,sans-serif">${code}</text>
        <circle cx="160" cy="120" r="9" fill="oklch(var(--p))" stroke="oklch(var(--b1))" stroke-width="3"/>
        <circle cx="160" cy="120" r="22" fill="oklch(var(--p) / 0.2)"/>
        <text x="160" y="172" text-anchor="middle"
              font-size="11" letter-spacing="1"
              font-family="ui-monospace,SFMono-Regular,Menlo,monospace"
              fill="oklch(var(--bc) / 0.55)">${lat.toFixed(2)}, ${lon.toFixed(2)}</text>
      </svg>
    `
  }

  markActiveReelItem(idx) {
    if (!this.hasReelItemTarget) return
    this.reelItemTargets.forEach((el, i) => {
      el.classList.toggle("memory-reel-item--viewing", i === idx)
    })
  }

  flyTo(idx) {
    const chapter = this.chaptersValue[idx]
    if (!chapter) return
    document.dispatchEvent(
      new CustomEvent("memories:chapter-changed", {
        detail: {
          idx,
          lat: Number(chapter.lat),
          lon: Number(chapter.lon),
          name: chapter.name,
          period_label: chapter.period_label,
          date: chapter.date,
        },
      }),
    )
  }

  applyMapBlur(enabled) {
    if (!this.hasMapAreaTarget) return
    const cls = this.hasMapBlurredClass
      ? this.mapBlurredClass
      : "memory-map-blurred"
    this.mapAreaTarget.classList.toggle(cls, enabled)
  }

  startAutoAdvance() {
    this.clearAutoAdvance()
    if (this.autoAdvanceMsValue <= 0) return
    this.autoAdvanceTimer = setTimeout(
      () => this.next(),
      this.autoAdvanceMsValue,
    )
  }

  clearAutoAdvance() {
    if (this.autoAdvanceTimer) {
      clearTimeout(this.autoAdvanceTimer)
      this.autoAdvanceTimer = null
    }
  }
}
