// The playhead on the score: where playback is (from the transport's
// "score:playhead" events), or, in Play mode with nothing playing, where
// Play would start ("score:play-start"). The score follows it.

import {playheadAt, playheadSpan} from "./playhead"

const SVG = "http://www.w3.org/2000/svg"
// Following the playhead in Strip layout: past this share of the visible
// width (or off its left), the score jumps to put it this share in.
const TURN_AT = 0.85
const TURN_TO = 0.2
// A turn still under way after this long (ms) is asked for again.
const TURN_RETRY = 600
// While playing, whether to scroll is checked this often (ms).
const FOLLOW_EVERY = 100

export class PlayheadView {
  // `el`: the score element (inside #score-paper); `overlay`: an Overlay.
  constructor(el, overlay) {
    this.el = el
    this.overlay = overlay
    this.line = null
    this.playStart = null
    this.sounding = false
    this.turning = {}
  }

  // New geometry or mode (each update): the idle playhead is redrawn.
  update(geometry, mode) {
    this.geometry = geometry
    this.mode = mode
    this.showIdle()
  }

  // Where playback has reached (`tick`; null: it has stopped), kept in
  // view; after a skip (`jump`), scrolled to at once.
  playing({tick, jump}) {
    this.sounding = tick !== null
    if (tick === null) {
      this.idleAt = null
      return this.showIdle()
    }
    if (jump) this.followedAt = null
    // Whether to scroll is checked every FOLLOW_EVERY ms, not every frame:
    // measuring the line makes the browser lay out the whole score.
    const now = performance.now()
    const follow = now - (this.followedAt ?? -Infinity) >= FOLLOW_EVERY
    if (follow) this.followedAt = now
    this.draw(tick, follow)
  }

  // Where Play would start (null in Edit mode).
  waitAt(tick) {
    this.playStart = tick
    this.showIdle()
  }

  // In Play mode, with nothing playing or paused, the playhead waits where
  // Play would start. It is scrolled to only when that place changes, so
  // redraws don't pull the score back from wherever it was scrolled. Edit
  // mode has no playhead.
  showIdle() {
    if (this.mode !== "play") {
      this.idleAt = null
      return this.line?.remove()
    }
    if (this.sounding || this.playStart === null) return
    const moved = this.idleAt !== this.playStart
    this.idleAt = this.playStart
    this.draw(this.playStart, moved)
  }

  // The playhead at `tick`, scrolled into view if `follow`.
  draw(tick, follow) {
    const at = playheadAt(this.geometry, tick)
    if (!at) return

    if (!this.line) {
      this.line = document.createElementNS(SVG, "line")
      this.line.setAttribute("class", "playhead")
    }
    if (!this.line.isConnected) this.overlay.svg.appendChild(this.line)
    const {top, bottom} = playheadSpan(this.geometry)
    Object.entries({x1: at.x, x2: at.x, y1: at.system.y + top, y2: at.system.y + bottom}).forEach(([k, v]) =>
      this.line.setAttribute(k, v),
    )
    if (follow) this.follow()
  }

  // Strip: the score scrolls sideways in jumps, like turning pages. Either
  // layout: the window scrolls the playhead's system into view. A smooth
  // scroll is asked for once and left to run: asking again every frame (the
  // target creeps on with the playhead) restarts it from rest each time, so
  // it never gets anywhere. Only one still not done after TURN_RETRY ms
  // (say, scrolled away from by hand) is asked for again.
  follow() {
    const line = this.line.getBoundingClientRect()
    const paper = this.el.closest("#score-paper")

    const turn = (axis, needed, target, scroll) => {
      if (!needed) return delete this.turning[axis]
      const now = performance.now()
      if (now - (this.turning[axis] ?? -Infinity) < TURN_RETRY) return
      this.turning[axis] = now
      scroll(target)
    }

    if (paper && paper.scrollWidth > paper.clientWidth) {
      const box = paper.getBoundingClientRect()
      const left = line.left - box.left
      turn("x", left < 0 || left > box.width * TURN_AT, paper.scrollLeft + left - box.width * TURN_TO, (to) =>
        paper.scrollTo({left: to, behavior: "smooth"}),
      )
    }

    // Down the page: each new system, or one out of view, is centred in what
    // the window shows below the sticky palette.
    const palette = document.getElementById("palette")
    const viewTop = palette ? Math.max(0, palette.getBoundingClientRect().bottom) : 0
    const middle = viewTop + (window.innerHeight - viewTop) / 2
    const system = this.line.getAttribute("y1")
    const newSystem = system !== this.followedSystem
    this.followedSystem = system
    const hidden = line.top < viewTop || line.bottom > window.innerHeight

    turn("y", newSystem || hidden, window.scrollY + (line.top + line.bottom) / 2 - middle, (to) =>
      window.scrollTo({top: to, behavior: "smooth"}),
    )
  }
}
