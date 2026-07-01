import maplibregl from "maplibre-gl"

// Renders `style` over `bounds` into a detached canvas at exactly width x height.
// A hidden, non-interactive map at pixelRatio 1 means the GL backing store equals
// the target pixels (callers clamp width/height to the device GL limit first).
export async function captureBounds({ style, bounds, width, height, signal }) {
  const container = document.createElement("div")
  container.style.cssText = `position:fixed;left:-99999px;top:0;width:${width}px;height:${height}px;pointer-events:none;`
  document.body.appendChild(container)

  const map = new maplibregl.Map({
    container,
    style,
    bounds,
    fitBoundsOptions: { padding: 0, animate: false },
    interactive: false,
    attributionControl: false,
    preserveDrawingBuffer: true,
    fadeDuration: 0,
    pixelRatio: 1,
  })

  try {
    await new Promise((resolve, reject) => {
      const onAbort = () => reject(new Error("Poster export aborted"))
      map.once("idle", () => {
        signal?.removeEventListener("abort", onAbort)
        resolve()
      })
      map.once("error", (event) =>
        reject(event.error ?? new Error("MapLibre error")),
      )
      signal?.addEventListener("abort", onAbort, { once: true })
    })

    const out = document.createElement("canvas")
    out.width = width
    out.height = height
    out.getContext("2d").drawImage(map.getCanvas(), 0, 0, width, height)
    return out
  } finally {
    map.remove()
    container.remove()
  }
}
