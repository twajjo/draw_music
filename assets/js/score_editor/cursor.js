// A CSS cursor showing a Bravura glyph, drawn on a canvas with the page's
// loaded font, so the pointer looks like the piece being placed.

const SIZE = 40
const FONT_PX = 28

export function cursorFor(char, color) {
  const canvas = document.createElement("canvas")
  canvas.width = SIZE
  canvas.height = SIZE
  const ctx = canvas.getContext("2d")
  ctx.font = `${FONT_PX}px Bravura`
  ctx.fillStyle = color || "#000"
  ctx.fillText(char, 8, SIZE - 10)
  // Hotspot near the notehead (glyph origin).
  return `url(${canvas.toDataURL()}) 12 ${SIZE - 12}, crosshair`
}
