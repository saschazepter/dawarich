const STROKE_BY_STYLE = {
  light: "#1e3a8a",
  white: "#1e3a8a",
  grayscale: "#1e3a8a",
  dark: "#ffffff",
  black: "#ffffff",
}

export function getMarkerStrokeColor(styleName) {
  return STROKE_BY_STYLE[styleName] ?? "#ffffff"
}
