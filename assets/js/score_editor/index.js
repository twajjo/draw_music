// ScoreEditor hook: the instant parts of editing. It maps the pointer to a
// musical position (geometry.js), draws the armed piece as the cursor and
// a dragged note where it would land, sounds each new line or space while
// the button is down, and sends semantic events (`place`, `drop`, `select`)
// to EditorLive, which owns the score.
//
// A press on a note or rest selects it when let go where it was pressed,
// even with a piece armed; a note dragged away lands where it is let go.
// With a piece armed, a press anywhere else shows and sounds it, and
// letting go places it.
//
// Server state arrives as data attributes on the hook element:
// data-geometry (EditorGeometry.encode), data-armed (EditorGeometry.armed),
// data-insert (Insert mode)
// and data-instrument (InstrumentSource). Playback lives in audio.js; the
// hook draws its playhead and keeps it in view.

import {locate, snap, xAt, columnAt, insertColumn, pitchOf, keyAlter, stepY, ledgerSteps, stepOnStaff, staffStepAt, stepAtY} from "./geometry"
import {chordAt} from "./chord"
import {cursorFor} from "./cursor"
import {playheadAt, playheadSpan, secondsAt, tickAt} from "./playhead"
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
const PLACEMENT_TONE = 0.25
// Chord preview (staff spaces): a second's upper note sits this far right;
// the name sits this far above the top note, at this size.
const SECOND_OFFSET = 1.2
const CHORD_LABEL_GAP = 2
const CHORD_LABEL_SIZE = 1.6
// About a notehead's width (staff spaces): a click this far right of a
// column is still on its note or rest.
const HEAD_WIDTH = 1.3
// Following the playhead in Strip layout: past this share of the visible
// width (or off its left), the score jumps to put it this share in.
const TURN_AT = 0.85
const TURN_TO = 0.2
// A turn still under way after this long (ms) is asked for again.
const TURN_RETRY = 600
// While playing, whether to scroll is checked this often (ms).
const FOLLOW_EVERY = 100

// The note, rest or tempo mark (and its id) under an event, if any. A
// tempo mark's label is "tempo"; a rit.'s or accel.'s end is "tempo-end".
function eventTarget(e) {
  const el = e.target.closest && e.target.closest("[id^='note-'], [id^='rest-'], [id^='tempo-']")
  if (!el) return null
  if (el.id.startsWith("tempo-end-")) return {kind: "tempo-end", id: el.id.slice(10)}
  if (el.id.startsWith("tempo-")) return {kind: "tempo", id: el.id.slice(6)}
  return {kind: el.id.startsWith("note-") ? "note" : "rest", id: el.id.slice(5)}
}

const tempoKind = (hit) => hit && (hit.kind === "tempo" || hit.kind === "tempo-end")

// The column (or the measure's end) whose x is nearest `x`: {offset, x}.
function nearestColumn(measure, x) {
  const ends = [{offset: 0, x: measure.content_x}, {offset: measure.capacity, x: measure.content_end}]
  const spots = [...measure.columns, ...ends]
  return spots.reduce((best, spot) => (Math.abs(spot.x - x) < Math.abs(best.x - x) ? spot : best))
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
      if (this.tempoDrag) return this.moveTempoDrag(e)
      if (this.band) return this.dragBand(e)
      if (this.pending) return this.movePending(e)
      if (this.drag) return this.moveDrag(e)
      if (this.tieDrag) return this.dragTie(e)
      this.hover(e)
    }
    this.onLeave = () => this.pressing || this.clearGhost()
    this.onDown = (e) => this.pointerDown(e)
    this.onUp = (e) => this.pointerUp(e)
    this.onCancel = () => this.cancelPress()
    this.onKey = (e) => this.key(e)
    this.onContext = (e) => this.contextMenu(e)
    // Double-clicking a tempo mark opens its dialog.
    this.onDoubleClick = (e) => {
      const hit = eventTarget(e)
      if (this.mode === "edit" && tempoKind(hit)) this.pushEvent("edit_tempo", {id: hit.id})
    }
    // Browsers allow audio only after a gesture: the first press, of a
    // pointer or a key, starts the audio clocks.
    this.onFirstGesture = () => {
      window.removeEventListener("pointerdown", this.onFirstGesture)
      window.removeEventListener("keydown", this.onFirstGesture)
      this.audio.unlock()
    }

    this.el.addEventListener("pointermove", this.onMove)
    this.el.addEventListener("pointerleave", this.onLeave)
    // A press anywhere on the paper counts, margins included: a rubber band
    // is often started just above and left of the music.
    this.paper = this.el.closest("#score-paper") || this.el
    this.paper.addEventListener("pointerdown", this.onDown)
    this.el.addEventListener("pointerup", this.onUp)
    this.el.addEventListener("pointercancel", this.onCancel)
    this.el.addEventListener("dblclick", this.onDoubleClick)
    window.addEventListener("keydown", this.onKey)
    // The palette's Pause and Stop buttons, before their click reaches the server.
    this.onTransport = (e) => {
      const button = e.target.closest && e.target.closest("#palette-play, #palette-stop")
      if (button?.id === "palette-play") this.pauseNow()
      if (button?.id === "palette-stop" && this.audio.state !== "idle") this.audio.stop(true)
    }
    document.addEventListener("click", this.onTransport, true)
    window.addEventListener("contextmenu", this.onContext)
    window.addEventListener("pointerdown", this.onFirstGesture)
    window.addEventListener("keydown", this.onFirstGesture)

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
      onTick: (seconds) => this.showPlayhead(seconds),
    })
    this.loadInstrument()
    this.handleEvent("play", ({events, span, loop, anchors}) => {
      this.anchors = anchors
      this.audio.play(events, span, Boolean(loop))
    })
    this.handleEvent("pause", () => this.audio.pause())
    this.handleEvent("resume", () => this.audio.resume())
    this.handleEvent("rewind", () => this.audio.rewind())
    this.handleEvent("skip", ({by}) => this.skip(by))
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
    document.removeEventListener("click", this.onTransport, true)
    window.removeEventListener("contextmenu", this.onContext)
    window.removeEventListener("pointerdown", this.onFirstGesture)
    window.removeEventListener("keydown", this.onFirstGesture)
    this.paper.removeEventListener("pointerdown", this.onDown)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    window.removeEventListener("popstate", this.onPopState)
    this.audio.destroy()
    document.removeEventListener("click", this.onLinkClick, true)
    this.setPageCursor(null)
  },

  readState() {
    this.geometry = JSON.parse(this.el.dataset.geometry)
    this.armed = JSON.parse(this.el.dataset.armed || "null")
    this.mode = this.el.dataset.mode || "edit"
    this.insert = this.el.dataset.insert === "true"
    this.el.classList.toggle("play-mode", this.mode === "play")
    this.overlay.setAttribute("viewBox", this.score.getAttribute("viewBox"))
    this.setPageCursor(this.armed && this.armed.glyph)
    if (!this.armed && !this.drag) this.clearGhost()
    this.playStart = this.el.dataset.playStart ? Number(this.el.dataset.playStart) : null
    this.showIdlePlayhead()
    this.showLoading(this.el.dataset.loading === "true")
  },

  // The "Loading the score…" note: once the score has arrived, it says the
  // score is being drawn and goes once the browser has painted it (a long
  // score takes a while), so the paper never looks empty.
  showLoading(loading) {
    const note = document.getElementById("score-loading")
    if (!note || note.hidden) return
    if (loading) return
    document.getElementById("score-loading-text").textContent = "Drawing the score…"
    requestAnimationFrame(() => requestAnimationFrame(() => (note.hidden = true)))
  },

  // Pointer → staff-space coordinates of the score's viewBox.
  toScore(e) {
    const point = this.score.createSVGPoint()
    point.x = e.clientX
    point.y = e.clientY
    return point.matrixTransform(this.score.getScreenCTM().inverse())
  },

  // Where the armed piece would land, or null, and where its ghost goes
  // (ghostX). Like a text editor: in Insert, the piece goes in front of the
  // note or rest whose notehead ends right of the pointer, its ghost in that
  // item's insertion gap; past a bar's last item it follows the music. In
  // Overlay, a note or rest's gap or head means its start; anywhere else
  // the beat grid, and it types over the time it covers.
  target(e) {
    if (!this.armed || !this.armed.glyph) return null
    const {x, y} = this.toScore(e)
    const at = locate(this.geometry, x, y)
    if (!at) return null

    const modifier = e.shiftKey ? 1 : e.ctrlKey || e.altKey ? -1 : null
    const {measure} = at
    const gridded = snap(at.offset, this.armed.grid, measure.capacity)

    if (this.insert) {
      const column = insertColumn(measure, at.staff, x, HEAD_WIDTH)
      if (column) return {...at, offset: column.offset, ghostX: column.x - measure.gap / 2 - HEAD_WIDTH / 2, modifier}
      return {...at, offset: gridded, ghostX: xAt(measure, gridded), modifier}
    }

    const column = columnAt(measure, at.staff, x, HEAD_WIDTH)
    const offset = column ? column.offset : gridded
    return {...at, offset, ghostX: xAt(measure, offset), modifier}
  },

  // The ghost follows the pointer; it sounds only while the button is down.
  hover(e) {
    const t = this.target(e)
    if (!t) return this.clearGhost()
    this.drawGhost(t)

    if (!this.pressing || this.armed.kind === "rest") return
    const alter = t.modifier ?? this.armed.alter
    const sound = `${t.staff}:${t.step}:${alter}`
    if (sound !== this.lastSound) {
      this.lastSound = sound
      const chord = chordAt(this.armed, t, this.geometry.sf)
      this.play(chord ? chord.tones.map((tone) => tone.midi) : pitchOf(t.step, alter, this.geometry.sf))
    }
  },

  pointerDown(e) {
    if (e.button !== 0) return
    // The bar controls are ordinary buttons.
    if (e.target.closest("button")) return
    // In the paper's margin, outside the music, a press only starts a band.
    if (!this.el.contains(e.target)) return this.startBand(e)

    const hit = eventTarget(e)
    // Play mode: a note sounds its chord; anywhere else starts a range selection.
    if (this.mode === "play" && hit) return hit.kind === "note" && this.pushEvent("audition", {id: hit.id})
    if (this.mode === "play") return this.startBand(e)
    if (this.armed && this.armed.kind === "tie") return hit && hit.kind === "note" && this.startTie(e, hit)
    if (this.armed && !hit) return this.startPress(e)

    // A tempo mark: selected on release, or dragged along the music.
    if (tempoKind(hit)) {
      this.pending = {hit, start: this.toScore(e), shift: e.shiftKey}
      return this.el.setPointerCapture(e.pointerId)
    }

    // A note or rest, armed or not: selected on release, unless a note is
    // dragged first. (A chord is stacked by pressing another line or space
    // at the note's start, which is not on the note itself.)
    if (hit) {
      this.pending = {hit, start: this.toScore(e), shift: e.shiftKey}
      return this.el.setPointerCapture(e.pointerId)
    }

    this.startBand(e)
  },

  startBand(e) {
    const start = this.toScore(e)
    this.band = {start, end: start}
    this.el.setPointerCapture(e.pointerId)
  },

  // Placing: the press sounds the armed piece, each new line or space
  // sounds while it is held, and letting go places it.
  startPress(e) {
    this.pressing = true
    this.lastSound = null
    this.el.setPointerCapture(e.pointerId)
    this.hover(e)
  },

  // A press on a note becomes a drag once the pointer has moved far enough.
  movePending(e) {
    const {hit, start} = this.pending
    const point = this.toScore(e)
    if (Math.hypot(point.x - start.x, point.y - start.y) < DRAG_THRESHOLD) return
    if (tempoKind(hit)) {
      this.pending = null
      this.tempoDrag = {hit, start}
      return this.moveTempoDrag(e)
    }
    if (hit.kind !== "note") return
    this.pending = null
    this.startDrag(hit)
    this.moveDrag(e)
  },

  // The pressed note drags alone, or with the selection if it is selected.
  // One note on its own may move to the other staff; several keep their staves.
  startDrag(hit) {
    const pressed = document.getElementById(`note-${hit.id}`)
    const elements = pressed.classList.contains("selected")
      ? [...this.score.querySelectorAll(".selected[id^='note-']")]
      : [pressed]

    const notes = elements.map((el) => {
      const staff = el.dataset.staff
      const y = Number(el.getAttribute("y"))
      const system = this.geometry.systems[Number(el.closest("[id^='system-']").id.slice(7))]
      return {el, id: el.id.slice(5), staff, step: stepAtY(this.geometry, staff, y), x: Number(el.getAttribute("x")), system}
    })

    const anchor = notes.find((note) => note.id === hit.id)
    elements.forEach((el) => el.classList.add("dragging"))
    // delta starts unset, so the first move draws and sounds the preview.
    this.drag = {notes, anchor, single: notes.length === 1, delta: null, staff: anchor.staff, modifier: null}
  },

  // Where the dragged notes would land, drawn and sounded on each change.
  moveDrag(e) {
    const point = this.toScore(e)
    const {anchor} = this.drag
    const modifier = e.shiftKey ? 1 : e.ctrlKey || e.altKey ? -1 : null
    const {staff, step} = this.drag.single
      ? staffStepAt(this.geometry, anchor.system, point.y)
      : {staff: anchor.staff, step: stepOnStaff(this.geometry, anchor.system, anchor.staff, point.y)}
    const delta = step - anchor.step

    if (delta === this.drag.delta && staff === this.drag.staff && modifier === this.drag.modifier) return
    Object.assign(this.drag, {delta, staff, modifier})
    this.drawDrag()
    this.play(this.dragTargets().map((t) => pitchOf(t.step, modifier, this.geometry.sf)))
  },

  // Each dragged note's landing place: its staff (the pointer's, for one
  // note alone) and step.
  dragTargets() {
    const {notes, single, staff, delta} = this.drag
    return notes.map((note) => ({...note, staff: single ? staff : note.staff, step: note.step + delta}))
  },

  // Lands the dragged notes. Let go where it started, the drag is a click.
  endDrag(e) {
    const {single, staff, delta, modifier, anchor} = this.drag
    const targets = this.dragTargets()
    this.cancelDrag()
    if (delta === 0 && staff === anchor.staff && modifier === null) return this.select({hit: anchor, shift: e.shiftKey})

    const ids = targets.map((t) => t.id)
    const params = single ? {ids, staff, step: targets[0].step} : {ids, steps: delta}
    if (modifier !== null) params.alter = modifier
    this.pushEvent("drop", params)
  },

  cancelDrag() {
    if (!this.drag) return
    this.drag.notes.forEach((note) => note.el.classList.remove("dragging"))
    this.drag = null
    this.clearGhost()
  },

  // A dragged tempo mark (or a rit.'s end) snaps to the nearest note or rest
  // column; a line shows where it would land.
  moveTempoDrag(e) {
    const point = this.toScore(e)
    const at = locate(this.geometry, point.x, this.tempoDrag.start.y)
    if (!at) return
    const target = nearestColumn(at.measure, point.x)
    this.tempoDrag.tick = at.measure.start_tick + target.offset
    this.clearGhost()
    const {top, bottom} = playheadSpan(this.geometry)
    const line = document.createElementNS(SVG, "line")
    Object.entries({
      x1: target.x, x2: target.x, y1: at.system.y + top - 2, y2: at.system.y + bottom,
      stroke: "var(--score-selection)", "stroke-width": 0.2, "stroke-dasharray": "0.5 0.3",
    }).forEach(([k, v]) => line.setAttribute(k, v))
    this.overlay.appendChild(line)
  },

  endTempoDrag() {
    const {hit, tick} = this.tempoDrag
    this.tempoDrag = null
    this.clearGhost()
    if (tick === undefined) return
    this.pushEvent(hit.kind === "tempo" ? "move_tempo" : "resize_tempo", {id: hit.id, tick})
  },

  // A click on a note, rest or tempo mark: Shift toggles it, else it alone is selected.
  select({hit, shift}) {
    this.pushEvent("select", {ids: [hit.id], add: shift})
  },

  // Abandons whatever the pointer was doing.
  cancelPress() {
    this.pending = null
    this.pressing = false
    this.band = null
    this.tieDrag = null
    this.tempoDrag = null
    this.cancelDrag()
    this.clearGhost()
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
    if (this.tempoDrag) return this.endTempoDrag()
    if (this.tieDrag) return this.endTie(e)
    if (this.drag) return this.endDrag(e)
    if (this.pending) {
      const pending = this.pending
      this.pending = null
      return this.select(pending)
    }
    if (this.pressing) {
      this.pressing = false
      return this.place(e)
    }
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
    if (document.querySelector("#settings-form, #save-as-form, #transpose-dialog, #help-dialog, #tempo-dialog")) return
    if (!KEYS.includes(keyId(e))) return
    const ctrl = e.ctrlKey || e.metaKey
    const k = e.key.toLowerCase()
    const send = (event, payload = {}) => {
      e.preventDefault()
      this.pushEvent(event, payload)
    }

    // Mode and help keys work in both modes.
    if (k === "p" && !ctrl && !e.altKey) return send("toggle_mode")
    if (e.key === "?") return send("open_help")
    if (this.mode === "play") return this.playKey(e, send)

    if (e.key === "Escape") {
      if (this.drag || this.pending) {
        e.preventDefault()
        return this.cancelPress()
      }
      this.pressing = false
      return send(this.armed ? "disarm" : "clear_selection")
    }

    // ↑/↓: a scale step (Shift: an octave, Ctrl: a semitone); ←/→: a beat.
    const dirs = {ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right"}
    if (dirs[e.key]) {
      const by = e.shiftKey ? "octave" : ctrl ? "semitone" : "step"
      return send("move", {dir: dirs[e.key], by})
    }

    if (ctrl && k === "z") return send(e.shiftKey ? "redo" : "undo")
    if (ctrl && k === "y") return send("redo")
    if (ctrl && k === "a") return send("select_all")
    if (ctrl && k === "c") return send("copy")
    if (ctrl && k === "x") return send("cut")
    if (ctrl && k === "v") return send("paste")
    if (ctrl || e.altKey) return
    if (e.key === "Delete" || e.key === "Backspace") return send("delete")
    if (e.key === "Insert") return send("toggle_insert")
    if (/^[1-7]$/.test(e.key)) return send("arm_value", {value: VALUES[Number(e.key) - 1]})
    if (e.key === "0") return send("disarm")
    if (k === "r") return send("toggle_rest")
    if (e.key === ".") return send("toggle_dot")
    if (k === "t") return send("arm_tie")
  },

  // Pausing and stopping happen here at once, not after the round trip to
  // the server; the server, told by the same key or click, then updates the
  // controls (and its own "pause" or "stop" finds nothing left to do).
  pauseNow() {
    if (this.audio.state === "playing") this.audio.pause(true)
  },

  // Play mode's keys: the play controls, and Esc to stop (or clear the selection).
  playKey(e, send) {
    if (e.ctrlKey || e.metaKey || e.altKey) return
    if (e.key === " ") {
      this.pauseNow()
      return send("play")
    }
    if (e.key === "Home") return send("rewind")
    if (e.key.toLowerCase() === "l") return send("toggle_loop")
    if (e.key === "Escape") {
      const sounding = this.audio.state === "playing" || this.audio.state === "paused"
      if (sounding) this.audio.stop(true)
      return send(sounding ? "stop" : "clear_selection")
    }
  },

  // Right-click: cancels placing or a drag; on a note or rest, opens its
  // menu (or the selection's, if it is selected).
  contextMenu(e) {
    if (this.mode === "play") return
    if (this.armed) {
      e.preventDefault()
      this.pressing = false
      return this.pushEvent("disarm", {})
    }
    if (this.drag || this.pending) {
      e.preventDefault()
      return this.cancelPress()
    }

    const hit = this.el.contains(e.target) && eventTarget(e)
    if (!hit) return
    e.preventDefault()
    if (tempoKind(hit)) return this.pushEvent("edit_tempo", {id: hit.id})
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

    const x = t.ghostX
    const chord = chordAt(this.armed, t, this.geometry.sf)
    if (chord) {
      this.drawChord(g, t, x, chord)
      return this.overlay.appendChild(g)
    }

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

  // A chord's noteheads where they'll land: ledger lines, the accidentals
  // the key doesn't already give, a second's upper note set off to the
  // right, and the chord's name above it.
  drawChord(g, t, x, chord) {
    const {geometry} = this
    let previous = null
    let top = Infinity

    for (const tone of chord.tones) {
      const y = stepY(geometry, t.staff, tone.step)
      const nx = previous !== null && tone.step - previous.step === 1 && !previous.shifted ? x + SECOND_OFFSET : x
      previous = {step: tone.step, shifted: nx !== x}
      top = Math.min(top, y)

      for (const step of ledgerSteps(geometry, t.staff, tone.step)) {
        const ly = stepY(geometry, t.staff, step)
        const line = document.createElementNS(SVG, "line")
        Object.entries({x1: nx - 0.4, x2: nx + 1.6, y1: ly, y2: ly, stroke: "currentColor", "stroke-width": 0.16}).forEach(([k, v]) => line.setAttribute(k, v))
        g.appendChild(line)
      }
      if (tone.alter !== keyAlter(geometry.sf, tone.step)) g.appendChild(this.glyph(ACCIDENTALS[tone.alter], x - 1.3, y))
      g.appendChild(this.glyph(this.armed.glyph, nx, y))
    }

    const label = document.createElementNS(SVG, "text")
    Object.entries({x, y: top - CHORD_LABEL_GAP, "font-family": "sans-serif", "font-size": CHORD_LABEL_SIZE}).forEach(([k, v]) => label.setAttribute(k, v))
    label.textContent = chord.label
    g.appendChild(label)
  },

  // The dragged notes' heads where they would land, with their ledger
  // lines and the accidental a modifier adds; the originals stay faded.
  drawDrag() {
    this.clearGhost()
    const {anchor, modifier} = this.drag
    const g = document.createElementNS(SVG, "g")
    g.setAttribute("transform", `translate(0 ${anchor.system.y})`)
    g.setAttribute("fill", "currentColor")
    g.setAttribute("opacity", "0.6")
    g.style.color = "var(--score-ink)"

    for (const t of this.dragTargets()) {
      const y = stepY(this.geometry, t.staff, t.step)
      for (const step of ledgerSteps(this.geometry, t.staff, t.step)) {
        const ly = stepY(this.geometry, t.staff, step)
        const line = document.createElementNS(SVG, "line")
        Object.entries({x1: t.x - 0.4, x2: t.x + 1.6, y1: ly, y2: ly, stroke: "currentColor", "stroke-width": 0.16}).forEach(([k, v]) => line.setAttribute(k, v))
        g.appendChild(line)
      }
      if (modifier !== null) g.appendChild(this.glyph(ACCIDENTALS[modifier], t.x - 1.3, y))
      g.appendChild(this.glyph(t.el.textContent, t.x, y))
    }
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

  // Empties the overlay, all but the playhead.
  clearGhost() {
    for (const child of [...this.overlay.children]) if (child !== this.playhead) child.remove()
  },

  // The playhead `seconds` into the span being played (null: none), kept
  // in view.
  showPlayhead(seconds) {
    if (seconds === null) {
      this.idleAt = null
      return this.showIdlePlayhead()
    }
    if (!this.anchors?.length) return
    // Whether to scroll is checked every FOLLOW_EVERY ms, not every frame:
    // measuring the line makes the browser lay out the whole score.
    const now = performance.now()
    const follow = now - (this.followedAt ?? -Infinity) >= FOLLOW_EVERY
    if (follow) this.followedAt = now
    this.drawPlayhead(tickAt(this.anchors, seconds), follow)
  },

  // Playing or paused: on to the start of the next measure ("measure") or
  // line of music ("line") inside the span being played, if there is one.
  skip(by) {
    const state = this.audio.state
    if ((state !== "playing" && state !== "paused") || !this.anchors?.length) return
    const now = tickAt(this.anchors, this.audio.position())
    const starts =
      by === "line"
        ? this.geometry.systems.map((s) => s.measures[0].start_tick)
        : this.geometry.systems.flatMap((s) => s.measures.map((m) => m.start_tick))
    const target = starts.find((tick) => tick > now + 0.5)
    if (target === undefined || target >= this.anchors[this.anchors.length - 1].tick) return
    // Scroll to it straight away.
    this.followedAt = null
    this.audio.seek(secondsAt(this.anchors, target))
  },

  // In Play mode, with nothing playing or paused, the playhead waits where
  // Play would start (data-play-start: the selection's start, or the
  // beginning). It is scrolled to only when that place changes, so redraws
  // don't pull the score back from wherever it was scrolled. Edit mode has
  // no playhead.
  showIdlePlayhead() {
    if (this.mode !== "play") {
      this.idleAt = null
      return this.playhead?.remove()
    }
    const state = this.audio?.state
    if (state === "playing" || state === "paused" || this.playStart === null) return
    const moved = this.idleAt !== this.playStart
    this.idleAt = this.playStart
    this.drawPlayhead(this.playStart, moved)
  },

  // The playhead at `tick`, scrolled into view if `follow`.
  drawPlayhead(tick, follow) {
    const at = playheadAt(this.geometry, tick)
    if (!at) return

    if (!this.playhead) {
      this.playhead = document.createElementNS(SVG, "line")
      this.playhead.setAttribute("class", "playhead")
    }
    if (!this.playhead.isConnected) this.overlay.appendChild(this.playhead)
    const {top, bottom} = playheadSpan(this.geometry)
    Object.entries({x1: at.x, x2: at.x, y1: at.system.y + top, y2: at.system.y + bottom}).forEach(([k, v]) => this.playhead.setAttribute(k, v))
    if (follow) this.followPlayhead()
  },

  // Strip: the score scrolls sideways in jumps, like turning pages. Either
  // layout: the window scrolls the playhead's system into view. A smooth
  // scroll is asked for once and left to run: asking again every frame (the
  // target creeps on with the playhead) restarts it from rest each time, so
  // it never gets anywhere. Only one still not done after TURN_RETRY ms
  // (say, scrolled away from by hand) is asked for again.
  followPlayhead() {
    const line = this.playhead.getBoundingClientRect()
    const paper = this.el.closest("#score-paper")
    this.turning = this.turning || {}

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
    const system = this.playhead.getAttribute("y1")
    const newSystem = system !== this.followedSystem
    this.followedSystem = system
    const hidden = line.top < viewTop || line.bottom > window.innerHeight

    turn("y", newSystem || hidden, window.scrollY + (line.top + line.bottom) / 2 - middle, (to) =>
      window.scrollTo({top: to, behavior: "smooth"}),
    )
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

  // The tone for placing and dragging, on the playback instrument: one
  // MIDI number, or a chord's, sounded together.
  play(midis) {
    this.audio.preview([midis].flat(), PLACEMENT_TONE)
  },
}
