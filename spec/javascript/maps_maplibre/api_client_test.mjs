import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../../app/javascript/maps_maplibre/services/api_client.js",
    import.meta.url,
  ),
  "utf8",
)
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const { ApiClient } = await import(moduleUrl)

test("fetchAllPoints requests metadata once and returns ordered points", async (t) => {
  const originalFetch = globalThis.fetch
  const urls = []
  const batches = []
  const progress = []
  t.after(() => {
    globalThis.fetch = originalFetch
  })

  globalThis.fetch = async (url) => {
    urls.push(url)
    const page = Number(
      new URL(url, "http://example.test").searchParams.get("page"),
    )
    const headers =
      page === 1 ? { "X-Total-Pages": "3", "X-Total-Points-In-Range": "3" } : {}
    return new Response(JSON.stringify([{ id: page }]), {
      status: 200,
      headers,
    })
  }

  const client = new ApiClient("secret")
  const result = await client.fetchAllPoints({
    start_at: 1,
    end_at: 2,
    maxConcurrent: 2,
    onProgress: (value) => progress.push(value),
    onBatch: (value) => batches.push(value),
  })

  assert.deepEqual(
    result.points.map(({ id }) => id),
    [1, 2, 3],
  )
  assert.equal(
    new URL(urls[0], "http://example.test").searchParams.has(
      "include_metadata",
    ),
    false,
  )
  assert.equal(
    new URL(urls[1], "http://example.test").searchParams.get(
      "include_metadata",
    ),
    "false",
  )
  assert.equal(
    new URL(urls[2], "http://example.test").searchParams.get(
      "include_metadata",
    ),
    "false",
  )
  assert.equal(batches.length, 0)
  assert.equal(progress.at(-1).loaded, 3)
  assert.equal(progress.at(-1).progress, 1)
})
