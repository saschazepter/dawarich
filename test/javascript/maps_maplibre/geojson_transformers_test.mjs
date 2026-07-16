import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { pathToFileURL } from "node:url"
import vm from "node:vm"

const repoRoot = path.resolve(import.meta.dirname, "../../..")
const moduleCache = new Map()

async function loadModule(relativePath) {
  const absolutePath = path.resolve(repoRoot, relativePath)
  const url = pathToFileURL(absolutePath).href

  if (moduleCache.has(url)) return moduleCache.get(url)

  const source = await readFile(absolutePath, "utf8")
  const mod = new vm.SourceTextModule(source, {
    identifier: url,
    initializeImportMeta(meta) {
      meta.url = url
    },
  })
  moduleCache.set(url, mod)

  await mod.link((specifier, referencingModule) => {
    const parentPath = new URL(referencingModule.identifier).pathname
    const resolvedPath = path.resolve(
      path.dirname(parentPath),
      `${specifier}.js`,
    )
    const relative = path.relative(repoRoot, resolvedPath)
    return loadModule(relative)
  })
  await mod.evaluate()

  return mod
}

const transformers = await loadModule(
  "app/javascript/maps_maplibre/utils/geojson_transformers.js",
)
const { pointsToGeoJSON, simplifyPointsForRendering } = transformers.namespace

function point(id, latitude, longitude, timestamp) {
  return { id, latitude, longitude, timestamp }
}

test("simplified point rendering keeps first point and drops nearby dense points", () => {
  const points = [
    point(1, 52.52, 13.405, 1_700_000_000),
    point(2, 52.52001, 13.40501, 1_700_000_010),
    point(3, 52.52002, 13.40502, 1_700_000_015),
    point(4, 52.521, 13.405, 1_700_000_016),
  ]

  assert.deepEqual(
    simplifyPointsForRendering(points).map((p) => p.id),
    [1, 4],
  )
})

test("simplified point rendering keeps points separated by time", () => {
  const points = [
    point(1, 52.52, 13.405, 1_700_000_000),
    point(2, 52.52001, 13.40501, 1_700_000_021),
  ]

  assert.deepEqual(
    pointsToGeoJSON(points, { simplified: true }).features.map(
      (feature) => feature.properties.id,
    ),
    [1, 2],
  )
})

test("raw point rendering keeps dense points", () => {
  const points = [
    point(1, 52.52, 13.405, 1_700_000_000),
    point(2, 52.52001, 13.40501, 1_700_000_010),
  ]

  assert.deepEqual(
    pointsToGeoJSON(points).features.map((feature) => feature.properties.id),
    [1, 2],
  )
})
