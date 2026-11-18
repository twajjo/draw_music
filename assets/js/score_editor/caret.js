// The insertion cursor on the score: a caret line at the session's cursor
// tick (data-cursor), where the next paste (and MIDI entry) goes. Drawn in
// Edit mode only, in the selection colour, so it reads differently from the
// red playback line. It scrolls the score only when moved by a key
// (`reveal`), not after a click.

import {playheadAt, playheadSpan} from "./playhead"

const SVG = "http://www.w3.org/2000/svg"

export class Caret {
  // `overlay`: an Overlay, whose svg the caret is drawn in.
  constructor(overlay) {
    this.overlay = overlay
    this.line = null
  }

  // The caret moved by a key (Ctrl+Home, Ctrl+End): drawn at once, without
  // waiting for the server, and scrolled into the middle of the view.
  reveal(geometry, mode, tick, insert) {
    this.update(geometry, mode, tick, insert)
    if (this.line?.isConnected) this.line.scrollIntoView({block: "center", inline: "center", behavior: "smooth"})
  }

  // Each update: the caret at `tick` (null: none) on `geometry`, in `mode`.
  // It's steady in Insert mode (`insert`) and blinks in Overlay mode, where
  // what follows it would be overwritten.
  update(geometry, mode, tick, insert) {
    const at = mode === "edit" && tick !== null ? playheadAt(geometry, tick) : null
    if (!at) return this.line?.remove()

    if (!this.line) {
      this.line = document.createElementNS(SVG, "line")
      this.line.setAttribute("class", "insertion-caret")
    }
    this.line.classList.toggle("overwriting", !insert)
    if (!this.line.isConnected) this.overlay.svg.appendChild(this.line)

    const {top, bottom} = playheadSpan(geometry)
    const ends = {x1: at.x, x2: at.x, y1: at.system.y + top, y2: at.system.y + bottom}
    Object.entries(ends).forEach(([k, v]) => this.line.setAttribute(k, v))
  }
}
