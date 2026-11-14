// The selection band: dragged across the music, it selects what lies
// between where it was pressed and where it is, in either direction and
// across lines. What letting go would select lights up meanwhile (the
// server says what, `preview_range`); near the edge of what's in view, the
// score scrolls on.

import {locate} from "./geometry"

// Dragging within this many pixels of the view's edge (or past it) scrolls
// the score, up to this many pixels a frame.
const SCROLL_EDGE = 40
const SCROLL_MAX = 24

// Pixels to scroll this frame for a pointer at `at` between `low` and
// `high`: negative near (or past) low, positive near high, 0 between.
function edgeSpeed(at, low, high) {
  const below = at - (low + SCROLL_EDGE)
  const above = at - (high - SCROLL_EDGE)
  const depth = below < 0 ? below : above > 0 ? above : 0
  return Math.round(Math.min(SCROLL_MAX, Math.max(-SCROLL_MAX, (depth / SCROLL_EDGE) * SCROLL_MAX)))
}

function tickOf(at) {
  return at.measure.start_tick + at.offset
}

export class Band {
  // `el`: the score element (the banded notes are in it); `overlay`: an
  // Overlay; `geometry()`: the current geometry; `send(event, payload,
  // reply)`: to the server.
  constructor({el, overlay, geometry, send}) {
    this.el = el
    this.overlay = overlay
    this.geometry = geometry
    this.send = send
    this.from = null
  }

  get active() {
    return this.from !== null
  }

  // Starts at a point in staff spaces.
  start(point) {
    this.from = point
    this.to = point
    this.pointer = null
  }

  // The pointer moved: draw to it, scrolling if it's near an edge.
  drag(e) {
    this.pointer = {clientX: e.clientX, clientY: e.clientY}
    this.autoScroll()
    this.drawTo(this.pointer)
  }

  // Let go: where it went from and to, and the band is gone.
  finish() {
    const ends = {start: this.from, end: this.to}
    this.cancel()
    return ends
  }

  cancel() {
    this.from = null
    this.pointer = null
    this.overlay.clear()
    this.endPreview()
  }

  // While the pointer is near an edge of the view (under the sticky
  // palette, the window's bottom, or in Strip layout the paper's sides),
  // the score scrolls every frame, faster the nearer the pointer is, and
  // the band follows the music under the pointer.
  autoScroll() {
    if (this.scrolling) return
    const step = () => {
      if (!this.pointer) return (this.scrolling = false)
      const {clientX, clientY} = this.pointer
      const palette = document.getElementById("palette")
      const viewTop = palette ? Math.max(0, palette.getBoundingClientRect().bottom) : 0
      const dy = edgeSpeed(clientY, viewTop, window.innerHeight)
      const paper = this.el.closest("#score-paper")
      const sideways = paper && paper.scrollWidth > paper.clientWidth
      const box = sideways && paper.getBoundingClientRect()
      const dx = sideways ? edgeSpeed(clientX, box.left, box.right) : 0
      if (!dx && !dy) return (this.scrolling = false)

      const before = [window.scrollY, paper?.scrollLeft]
      window.scrollBy(0, dy)
      if (dx) paper.scrollLeft += dx
      // At the end of the page (or the strip) there's nowhere left to go.
      if (window.scrollY === before[0] && paper?.scrollLeft === before[1]) return (this.scrolling = false)
      this.drawTo(this.pointer)
      requestAnimationFrame(step)
    }
    this.scrolling = true
    requestAnimationFrame(step)
  }

  drawTo(pointer) {
    this.to = this.overlay.toScore(pointer)
    const {from: start, to: end} = this
    const geometry = this.geometry()
    this.overlay.clear()
    const a = locate(geometry, start.x, start.y)
    const b = locate(geometry, end.x, end.y)
    if (!a || !b) return

    const [first, last] =
      tickOf(a) < tickOf(b) || (tickOf(a) === tickOf(b) && start.x <= end.x)
        ? [{at: a, x: start.x}, {at: b, x: end.x}]
        : [{at: b, x: end.x}, {at: a, x: start.x}]
    this.overlay.band(geometry, first, last)
    this.preview(Math.round(tickOf(first.at)), Math.round(tickOf(last.at)))
  }

  // Asks the server what the range would select (one request at a time,
  // only when the range changes) and lights those notes and rests up.
  preview(from, to) {
    this.previewing = this.previewing || {}
    this.previewing.wanted = [from, to]
    const key = `${from}:${to}`
    if (this.previewing.waiting || key === this.previewing.shown) return
    this.previewing.waiting = true
    this.send("preview_range", {from, to}, ({ids}) => {
      // Let go (or cancelled) before the answer came.
      if (!this.previewing) return
      this.previewing.waiting = false
      this.previewing.shown = key
      this.light(ids)
      this.preview(...this.previewing.wanted)
    })
  }

  light(ids) {
    for (const el of this.el.querySelectorAll(".banded")) el.classList.remove("banded")
    for (const id of ids) {
      const el = document.getElementById(`note-${id}`) || document.getElementById(`rest-${id}`)
      if (el) el.classList.add("banded")
    }
  }

  endPreview() {
    this.previewing = null
    this.light([])
  }
}
