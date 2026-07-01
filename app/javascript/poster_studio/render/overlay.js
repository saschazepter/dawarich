function hexToRgba(hex, alpha) {
  const v = hex.replace("#", "")
  const n =
    v.length === 3
      ? v
          .split("")
          .map((c) => c + c)
          .join("")
      : v.padEnd(6, "0").slice(0, 6)
  const int = parseInt(n, 16)
  return `rgba(${(int >> 16) & 255}, ${(int >> 8) & 255}, ${int & 255}, ${alpha})`
}

function drawFades(ctx, width, height, color, strength) {
  const top = height * strength * 0.5
  const bottom = height * strength
  const topGrad = ctx.createLinearGradient(0, 0, 0, top)
  topGrad.addColorStop(0, hexToRgba(color, 0.9))
  topGrad.addColorStop(1, hexToRgba(color, 0))
  ctx.fillStyle = topGrad
  ctx.fillRect(0, 0, width, top)

  const botGrad = ctx.createLinearGradient(0, height - bottom, 0, height)
  botGrad.addColorStop(0, hexToRgba(color, 0))
  botGrad.addColorStop(1, hexToRgba(color, 0.97))
  ctx.fillStyle = botGrad
  ctx.fillRect(0, height - bottom, width, bottom)
}

function drawTitle(ctx, width, height, color, title, subtitle, font) {
  const citySize = Math.round(width * 0.075)
  const subSize = Math.round(width * 0.03)
  const baseY = height - Math.round(height * 0.055)
  ctx.textAlign = "center"
  ctx.fillStyle = color

  if (title) {
    ctx.font = `700 ${citySize}px ${font}`
    ctx.fillText(title.toUpperCase(), width / 2, baseY)
  }
  if (subtitle) {
    const dividerY = baseY + Math.round(subSize * 0.9)
    ctx.strokeStyle = color
    ctx.globalAlpha = 0.6
    ctx.lineWidth = Math.max(1, Math.round(width * 0.0015))
    ctx.beginPath()
    ctx.moveTo(width / 2 - width * 0.12, dividerY)
    ctx.lineTo(width / 2 + width * 0.12, dividerY)
    ctx.stroke()
    ctx.globalAlpha = 1
    ctx.font = `400 ${subSize}px ${font}`
    ctx.fillText(subtitle.toUpperCase(), width / 2, dividerY + subSize * 1.4)
  }
}

export function drawOverlay(
  canvas,
  {
    theme,
    title = "",
    subtitle = "",
    font = "Helvetica, Arial, sans-serif",
    fadeStrength = 0.22,
    margin = 0,
  },
) {
  const ctx = canvas.getContext("2d")
  const { width, height } = canvas

  if (margin > 0) {
    const m = Math.round(Math.min(width, height) * margin)
    ctx.fillStyle = theme.bg
    ctx.fillRect(0, 0, width, m)
    ctx.fillRect(0, height - m, width, m)
    ctx.fillRect(0, 0, m, height)
    ctx.fillRect(width - m, 0, m, height)
  }

  drawFades(ctx, width, height, theme.gradientColor, fadeStrength)
  if (title || subtitle)
    drawTitle(ctx, width, height, theme.text, title, subtitle, font)
  return canvas
}
