// The pointer while a piece is armed: a CSS cursor showing its Bravura
// glyph, drawn on a canvas with the page's loaded font.

const SIZE = 40
const FONT_PX = 28
const STYLE_ID = "score-editor-cursor"

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

// While armed (`char`: the piece's glyph): the piece as the pointer outside
// the score, no pointer over the score (`el`; the ghost is the cursor
// there). Null: the usual pointer.
export function setPageCursor(el, char) {
  document.getElementById(STYLE_ID)?.remove()
  if (!char) return
  const color = getComputedStyle(el).getPropertyValue("--score-ink").trim()
  const style = document.createElement("style")
  style.id = STYLE_ID
  style.textContent =
    `body, body * { cursor: ${cursorFor(char, color)} !important; }\n` +
    `#score-editor, #score-editor * { cursor: none !important; }`
  document.head.appendChild(style)
}
