export const DEFAULT_ROUTE_COLOR = "#FF3B30"
export const DEFAULT_CASING_COLOR = "#000000"

export const THEME_KEYS = [
  "autumn",
  "blueprint",
  "contrast_zones",
  "copper_patina",
  "emerald",
  "forest",
  "gradient_roads",
  "japanese_ink",
  "midnight_blue",
  "monochrome_blue",
  "neon_cyberpunk",
  "noir",
  "ocean",
  "pastel_dream",
  "sunset",
  "terracotta",
  "warm_beige",
]

// Mirrors the sidecar's route_overlay.py: route_color = theme.route or DEFAULT,
// casing = theme.bg. Keeps the browser track color identical to the print render.
export function resolveTheme(tokens) {
  return {
    name: tokens.name ?? "",
    description: tokens.description ?? "",
    bg: tokens.bg,
    text: tokens.text,
    gradientColor: tokens.gradient_color ?? tokens.bg,
    water: tokens.water,
    parks: tokens.parks,
    roads: {
      motorway: tokens.road_motorway,
      primary: tokens.road_primary,
      secondary: tokens.road_secondary,
      tertiary: tokens.road_tertiary,
      residential: tokens.road_residential,
      default: tokens.road_default,
    },
    route: tokens.route ?? DEFAULT_ROUTE_COLOR,
    casing: tokens.bg ?? DEFAULT_CASING_COLOR,
  }
}

const cache = new Map()

export async function loadTheme(key) {
  if (cache.has(key)) return cache.get(key)
  const response = await fetch(`/poster_themes/${key}.json`)
  if (!response.ok) {
    throw new Error(`Failed to load poster theme "${key}" (${response.status})`)
  }
  const resolved = resolveTheme(await response.json())
  cache.set(key, resolved)
  return resolved
}
