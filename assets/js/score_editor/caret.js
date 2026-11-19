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
    // The tick it's drawn at, and how many key moves the server hasn't
    // answered yet: until it has, its own (older) cursor is ignored, so a
    // held arrow key doesn't jump back.
    this.tick = null
    this.ahead = 0
  }

  // The caret moved by a key (an arrow, Ctrl+Home, Ctrl+End): drawn at
  // once, without waiting for the server, and scrolled into the middle of
  // the view. Returns the function to call once the server has the move.
  reveal(geometry, mode, tick, insert) {
    this.ahead += 1
    this.tick = tick
    this.draw(geometry, mode, insert)
    if (this.line?.isConnected) this.line.scrollIntoView({block: "center", inline: "center", behavior: "smooth"})
    return () => {
      this.ahead = Math.max(0, this.ahead - 1)
    }
  }

  // Each update: the caret at the server's `tick` (null: none) on
  // `geometry`, in `mode`, unless a key move is still on its way.
  update(geometry, mode, tick, insert) {
    if (this.ahead === 0) this.tick = tick
    this.draw(geometry, mode, insert)
  }

  // Steady in Insert mode (`insert`); blinking in Overlay mode, where what
  // follows it would be overwritten.
  draw(geometry, mode, insert) {
    const at = mode === "edit" && this.tick !== null ? playheadAt(geometry, this.tick) : null
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
