// ScoreEditor hook: the instant parts of editing. It maps the pointer to a
// musical position (geometry.js), draws the armed piece as the cursor,
// plays a tone on each new line or space, and sends semantic events
// (`place`, `disarm`) to EditorLive, which owns the score.
//
// Server state arrives as data attributes on the hook element:
// data-geometry (EditorGeometry.encode), data-armed (EditorGeometry.armed)
// and data-instrument (InstrumentSource). Playback lives in audio.js.

import * as Tone from "tone"
import {locate, snap, pitchOf, stepY, ledgerSteps, stepOnStaff} from "./geometry"
import {cursorFor} from "./cursor"
import {Audio} from "./audio"
// The keys this hook acts on; the cheat-sheet (DrawMusicWeb.Shortcuts) lists the same ones.
import KEYS from "./keys.json"

const SVG = "http://www.w3.org/2000/svg"
const CURSOR_STYLE_ID = "score-editor-cursor"
const ACCIDENTALS = {"-2": "", "-1": "", 0: "", 1: "", 2: ""}
const VALUES = ["whole", "half", "quarter", "eighth", "sixteenth", "thirty_second", "sixty_fourth"]
// A pointer drag shorter than this (staff spaces) is a click.
const DRAG_THRESHOLD = 0.5
// Clicks on empty staff remember a paste position on this grid (a 16th).
const CLICK_GRID = 240
// Length of the tone played over each new line or space (seconds).
const PLACEMENT_TONE = 0.12

// The note or rest element (and its id) under an event, if any.
function eventTarget(e) {
  const el = e.target.closest && e.target.closest("[id^='note-'], [id^='rest-']")
  return el && {kind: el.id.startsWith("note-") ? "note" : "rest", id: el.id.slice(5)}
}

const typing = (e) => e.target.closest && e.target.closest("input, textarea, select, [contenteditable]")

// A key press as keys.json names it: "Ctrl+Z", "Shift+ArrowUp", "Space", "R".
// Modifiers only count where they change what the key does.
function keyId(e) {
  const ctrl = e.ctrlKey || e.metaKey
  const name = e.key === " " ? "Space" : e.key.length === 1 ? e.key.toUpperCase() : e.key
  if (name === "ArrowUp" || name === "ArrowDown") return ctrl ? `Ctrl+${name}` : e.shiftKey ? `Shift+${name}` : name
  if (ctrl) return e.shiftKey ? `Ctrl+Shift+${name}` : `Ctrl+${name}`
  return name
}

export default {
  mounted() {
    this.score = this.el.querySelector("#score")
    this.overlay = this.el.querySelector("#score-overlay")
    this.lastSound = null
    this.readState()

    this.onMove = (e) => {
      if (this.band) return this.dragBand(e)
      if (this.lift) return this.moveLift(e)
      if (this.tieDrag) return this.dragTie(e)
      this.hover(e)
    }
    this.onLeave = () => this.clearGhost()
    this.onDown = (e) => this.pointerDown(e)
    this.onUp = (e) => this.pointerUp(e)
    this.onKey = (e) => this.key(e)
    this.onContext = (e) => this.contextMenu(e)
    this.onFirstGesture = () => this.startAudio()

    this.el.addEventListener("pointermove", this.onMove)
    this.el.addEventListener("pointerleave", this.onLeave)
    this.el.addEventListener("pointerdown", this.onDown)
    this.el.addEventListener("pointerup", this.onUp)
    window.addEventListener("keydown", this.onKey)
    window.addEventListener("contextmenu", this.onContext)
    window.addEventListener("pointerdown", this.onFirstGesture, {once: true})

    // Unsaved changes: confirm before leaving, by closing/reloading the tab
    // or by following an in-app link.
    this.onBeforeUnload = (e) => {
      if (!this.dirty()) return
      e.preventDefault()
      e.returnValue = ""
    }
    // The Back button: while there are unsaved changes, a guard entry for
    // this same page sits on top of the history. Going back lands on the
    // page's own entry (same address, so LiveView does nothing) and asks.
    this.onPopState = () => {
      if (!this.guarded) return
      this.guarded = false
      if (confirm("Leave without saving your changes?")) history.back()
      else this.syncGuard()
    }
    window.addEventListener("popstate", this.onPopState)
    this.syncGuard()

    // Playback: the server sends timed events; audio.js sounds and highlights them.
    this.audio = new Audio({
      onState: (state, source) => this.pushEvent("playback_state", {state, name: source && source.name}),
      onEnded: () => this.pushEvent("playback_ended", {}),
    })
    this.loadInstrument()
    this.handleEvent("play", ({events, loop}) => this.audio.play(events, Boolean(loop)))
    this.handleEvent("pause", () => this.audio.pause())
    this.handleEvent("resume", () => this.audio.resume())
    this.handleEvent("rewind", () => this.audio.rewind())
    this.handleEvent("loop", ({on}) => this.audio.setLoop(on))
    this.handleEvent("stop", () => this.audio.stop())
    this.handleEvent("audition", ({events}) => this.audio.audition(events))
    this.onLinkClick = (e) => {
      const link = e.target.closest && e.target.closest("a[href]")
      if (!link || !this.dirty() || link.hasAttribute("download")) return
      if (!confirm("Leave without saving your changes?")) {
        e.preventDefault()
        e.stopImmediatePropagation()
      }
    }
    window.addEventListener("beforeunload", this.onBeforeUnload)
    document.addEventListener("click", this.onLinkClick, true)
  },

  dirty() {
    return this.el.dataset.dirty === "true"
  },

  // Adds the history guard when changes become unsaved; removes it after a save.
  syncGuard() {
    if (this.dirty() && !this.guarded) {
      history.pushState({drawMusicGuard: true}, "", location.href)
      this.guarded = true
    } else if (!this.dirty() && this.guarded) {
      this.guarded = false
      history.back()
    }
  },

  updated() {
    this.score = this.el.querySelector("#score")
    this.readState()
    this.syncGuard()
    this.loadInstrument()
  },

  loadInstrument() {
    this.audio.load(JSON.parse(this.el.dataset.instrument))
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKey)
    window.removeEventListener("contextmenu", this.onContext)
    window.removeEventListener("pointerdown", this.onFirstGesture)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    window.removeEventListener("popstate", this.onPopState)
    this.audio.silence()
    document.removeEventListener("click", this.onLinkClick, true)
    this.setPageCursor(null)
  },

  readState() {
    this.geometry = JSON.parse(this.el.dataset.geometry)
    this.armed = JSON.parse(this.el.dataset.armed || "null")
    this.mode = this.el.dataset.mode || "edit"
    this.el.classList.toggle("play-mode", this.mode === "play")
    this.overlay.setAttribute("viewBox", this.score.getAttribute("viewBox"))
    this.setPageCursor(this.armed && this.armed.glyph)
    if (!this.armed) this.clearGhost()
  },

  // Pointer → staff-space coordinates of the score's viewBox.
  toScore(e) {
    const point = this.score.createSVGPoint()
    point.x = e.clientX
    point.y = e.clientY
    return point.matrixTransform(this.score.getScreenCTM().inverse())
  },

  // Where the armed piece would land, or null.
  target(e) {
    if (!this.armed || !this.armed.glyph) return null
    const {x, y} = this.toScore(e)
    const at = locate(this.geometry, x, y)
    if (!at) return null

    const offset = snap(at.offset, this.armed.grid, at.measure.capacity)
    const modifier = e.shiftKey ? 1 : e.ctrlKey || e.altKey ? -1 : null
    return {...at, offset, modifier}
  },

  hover(e) {
    const t = this.target(e)
    if (!t) return this.clearGhost()
    this.drawGhost(t)

    if (this.armed.kind === "rest") return
    const alter = t.modifier ?? this.armed.alter
    const sound = `${t.staff}:${t.step}:${alter}`
    if (sound !== this.lastSound) {
      this.lastSound = sound
      this.play(pitchOf(t.step, alter, this.geometry.sf))
    }
  },

  pointerDown(e) {
    if (e.button !== 0) return
    // The bar controls are ordinary buttons.
    if (e.target.closest("button")) return
    if (this.lift) return this.dropLift(e)

    const hit = eventTarget(e)
    // Play mode: a note sounds its chord; anywhere else starts a range selection.
    if (this.mode === "play" && hit) return hit.kind === "note" && this.pushEvent("audition", {id: hit.id})
    if (this.mode === "play") return this.startBand(e)
    if (this.armed && this.armed.kind === "tie") return hit && hit.kind === "note" && this.startTie(e, hit)
    if (this.armed) return this.place(e)

    if (hit) {
      // Shift-click toggles; a rest selects alone; a note is picked up.
      if (e.shiftKey) return this.pushEvent("select", {ids: [hit.id], add: true})
      if (hit.kind === "rest") return this.pushEvent("select", {ids: [hit.id], add: false})
      return this.startLift(e, hit)
    }

    this.startBand(e)
  },

  startBand(e) {
    const start = this.toScore(e)
    this.band = {start, end: start}
    this.el.setPointerCapture(e.pointerId)
  },

  // Pick-up: the clicked note (with the selection, if it is selected)
  // follows the pointer by scale steps until a second click drops it.
  startLift(e, hit) {
    const clicked = document.getElementById(`note-${hit.id}`)
    const elements = clicked.classList.contains("selected")
      ? [...this.score.querySelectorAll(".selected[id^='note-']")]
      : [clicked]
    const point = this.toScore(e)
    const at = locate(this.geometry, point.x, point.y)
    if (!at) return

    this.lift = {elements, ids: elements.map((el) => el.id.slice(5)), at, delta: 0, modifier: null}
    this.play(pitchOf(at.step, null, this.geometry.sf))
  },

  moveLift(e) {
    const point = this.toScore(e)
    const {at} = this.lift
    const delta = stepOnStaff(this.geometry, at.system, at.staff, point.y) - at.step
    const modifier = e.shiftKey ? 1 : e.ctrlKey || e.altKey ? -1 : null

    if (delta !== this.lift.delta || modifier !== this.lift.modifier) {
      this.lift.delta = delta
      this.lift.modifier = modifier
      this.lift.elements.forEach((el) => el.setAttribute("transform", `translate(0 ${-delta / 2})`))
      this.play(pitchOf(at.step + delta, modifier, this.geometry.sf))
    }
  },

  dropLift(e) {
    const {ids, delta, modifier} = this.endLift()
    if (delta === 0 && modifier === null) return
    const params = {ids, steps: delta}
    if (modifier !== null) params.alter = modifier
    e.preventDefault()
    this.pushEvent("drop", params)
  },

  // Puts lifted notes back; returns what was lifted.
  endLift() {
    const lift = this.lift
    this.lift = null
    lift.elements.forEach((el) => el.removeAttribute("transform"))
    return lift
  },

  // Tie tool: drag from one note to another.
  startTie(e, hit) {
    this.tieDrag = {from: hit.id, start: this.toScore(e)}
    this.el.setPointerCapture(e.pointerId)
  },

  dragTie(e) {
    const end = this.toScore(e)
    const {start} = this.tieDrag
    this.clearGhost()
    const line = document.createElementNS(SVG, "line")
    Object.entries({x1: start.x, y1: start.y, x2: end.x, y2: end.y, stroke: "var(--score-selection)", "stroke-width": 0.2, "stroke-dasharray": "0.5 0.3"}).forEach(([k, v]) => line.setAttribute(k, v))
    this.overlay.appendChild(line)
  },

  endTie(e) {
    const {from} = this.tieDrag
    this.tieDrag = null
    this.clearGhost()
    const under = document.elementFromPoint(e.clientX, e.clientY)
    const target = under && under.closest("[id^='note-']")
    if (target && target.id.slice(5) !== from) this.pushEvent("tie", {from, to: target.id.slice(5)})
  },

  pointerUp(e) {
    if (this.tieDrag) return this.endTie(e)
    if (!this.band) return
    const {start, end} = this.band
    this.band = null
    this.clearGhost()

    if (Math.hypot(end.x - start.x, end.y - start.y) < DRAG_THRESHOLD) {
      const at = this.tickAt(start)
      if (at !== null) this.pushEvent("set_last_click", {at: Math.floor(at / CLICK_GRID) * CLICK_GRID})
      this.pushEvent("clear_selection", {})
      return
    }

    const from = this.tickAt(start)
    const to = this.tickAt(end)
    if (from !== null && to !== null) this.pushEvent("select_range", {from: Math.round(from), to: Math.round(to)})
  },

  // Absolute tick at a point (by x, in the system the point is in).
  tickAt(point) {
    const at = locate(this.geometry, point.x, point.y)
    return at && at.measure.start_tick + at.offset
  },

  dragBand(e) {
    this.band.end = this.toScore(e)
    const {start, end} = this.band
    this.clearGhost()
    const rect = document.createElementNS(SVG, "rect")
    Object.entries({
      x: Math.min(start.x, end.x),
      y: Math.min(start.y, end.y),
      width: Math.abs(end.x - start.x),
      height: Math.abs(end.y - start.y),
      fill: "var(--score-selection)",
      "fill-opacity": 0.12,
      stroke: "var(--score-selection)",
      "stroke-width": 0.1,
    }).forEach(([k, v]) => rect.setAttribute(k, v))
    this.overlay.appendChild(rect)
  },

  place(e) {
    const t = this.target(e)
    if (!t) return
    const params = {measure: t.measure.index, offset: t.offset, staff: t.staff, step: t.step}
    if (t.modifier !== null) params.alter = t.modifier
    this.lastSound = null
    this.pushEvent("place", params)
  },

  key(e) {
    if (typing(e)) return
    // A dialog is open: its own keys (Esc) handle it; leave the score alone.
    if (document.querySelector("#settings-form, #save-as-form, #transpose-dialog, #help-dialog")) return
    if (!KEYS.includes(keyId(e))) return
    const ctrl = e.ctrlKey || e.metaKey
    const k = e.key.toLowerCase()
    const send = (event, payload = {}) => {
      e.preventDefault()
      this.pushEvent(event, payload)
    }

    if (e.key === "Escape") {
      if (this.audio.state === "playing" || this.audio.state === "paused") return send("stop")
      if (this.lift) {
        e.preventDefault()
        return this.endLift()
      }
      return send(this.armed ? "disarm" : "clear_selection")
    }

    // Playback and mode keys work in both modes; the rest only edit.
    if (e.key === " " && !ctrl) return send("play")
    if (e.key === "Home" && !ctrl) return send("rewind")
    if (k === "l" && !ctrl && !e.altKey) return send("toggle_loop")
    if (k === "p" && !ctrl && !e.altKey) return send("toggle_mode")
    if (e.key === "?") return send("open_help")
    if (this.mode === "play") return

    // ↑/↓: a scale step (Shift: an octave, Ctrl: a semitone); ←/→: a beat.
    const dirs = {ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right"}
    if (dirs[e.key]) {
      const by = e.shiftKey ? "octave" : ctrl ? "semitone" : "step"
      return send("move", {dir: dirs[e.key], by})
    }

    if (ctrl && k === "z") return send(e.shiftKey ? "redo" : "undo")
    if (ctrl && k === "y") return send("redo")
    if (ctrl && k === "c") return send("copy")
    if (ctrl && k === "x") return send("cut")
    if (ctrl && k === "v") return send("paste")
    if (ctrl || e.altKey) return
    if (e.key === "Delete" || e.key === "Backspace") return send("delete")
    if (e.key === "Insert") return send("toggle_insert")
    if (/^[1-7]$/.test(e.key)) return send("arm_value", {value: VALUES[Number(e.key) - 1]})
    if (k === "r") return send("toggle_rest")
    if (e.key === ".") return send("toggle_dot")
    if (k === "t") return send("arm_tie")
  },

  // Right-click: cancels placing or a pick-up; on a note or rest, opens
  // its menu (or the selection's, if it is selected).
  contextMenu(e) {
    if (this.mode === "play") return
    if (this.armed) {
      e.preventDefault()
      return this.pushEvent("disarm", {})
    }
    if (this.lift) {
      e.preventDefault()
      return this.endLift()
    }

    const hit = this.el.contains(e.target) && eventTarget(e)
    if (!hit) return
    e.preventDefault()
    const point = this.toScore(e)
    const at = locate(this.geometry, point.x, point.y)
    this.pushEvent("open_menu", {id: hit.id, x: e.clientX, y: e.clientY, step: at.step, staff: at.staff})
  },

  // The armed piece drawn where it would land, with ledger lines and the
  // accidental a modifier adds.
  drawGhost(t) {
    this.clearGhost()
    const g = document.createElementNS(SVG, "g")
    g.setAttribute("transform", `translate(0 ${t.system.y})`)
    g.setAttribute("fill", "currentColor")
    g.setAttribute("opacity", "0.6")
    g.style.color = "var(--score-ink)"

    const x = t.measure.content_x + t.offset * t.measure.scale
    const rest = this.armed.kind === "rest"
    const y = rest ? stepY(this.geometry, t.staff, this.geometry.top_step[t.staff] - 4) : stepY(this.geometry, t.staff, t.step)

    if (!rest) {
      for (const step of ledgerSteps(this.geometry, t.staff, t.step)) {
        const ly = stepY(this.geometry, t.staff, step)
        const line = document.createElementNS(SVG, "line")
        Object.entries({x1: x - 0.4, x2: x + 1.6, y1: ly, y2: ly, stroke: "currentColor", "stroke-width": 0.16}).forEach(([k, v]) => line.setAttribute(k, v))
        g.appendChild(line)
      }
      const alter = t.modifier ?? this.armed.alter
      if (alter !== null && alter !== undefined) g.appendChild(this.glyph(ACCIDENTALS[alter], x - 1.3, y))
    }

    g.appendChild(this.glyph(this.armed.glyph, x, y))
    this.overlay.appendChild(g)
  },

  glyph(char, x, y) {
    const text = document.createElementNS(SVG, "text")
    text.setAttribute("x", x)
    text.setAttribute("y", y)
    text.setAttribute("font-family", "Bravura")
    text.setAttribute("font-size", 4)
    text.textContent = char
    return text
  },

  clearGhost() {
    this.overlay.replaceChildren()
  },

  // While armed: the piece as the pointer outside the score, no pointer
  // over the score (the ghost is the cursor there).
  setPageCursor(char) {
    document.getElementById(CURSOR_STYLE_ID)?.remove()
    if (!char) return
    const color = getComputedStyle(this.el).getPropertyValue("--score-ink").trim()
    const style = document.createElement("style")
    style.id = CURSOR_STYLE_ID
    style.textContent =
      `body, body * { cursor: ${cursorFor(char, color)} !important; }\n` +
      `#score-editor, #score-editor * { cursor: none !important; }`
    document.head.appendChild(style)
  },

  // Browsers only allow audio after a user gesture.
  async startAudio() {
    await Tone.start()
    this.synth = new Tone.Synth({
      oscillator: {type: "triangle"},
      envelope: {attack: 0.005, decay: 0.1, sustain: 0.2, release: 0.2},
    }).toDestination()
  },

  // The placement beep (until parts bring per-instrument tones).
  play(midi) {
    if (this.synth) this.synth.triggerAttackRelease(Tone.Frequency(midi, "midi"), PLACEMENT_TONE)
  },
}
