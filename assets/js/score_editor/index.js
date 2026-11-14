// ScoreEditor hook: the instant parts of editing, as glue over the
// libraries beside it. It maps the pointer to a musical position, shows the
// armed piece (placing.js, overlay.js) and dragged notes (note_drag.js)
// where they would land, sounds each new line or space while the button is
// down, runs the selection band (band.js), and sends semantic events
// (`place`, `drop`, `select`, …) to EditorLive, which owns the score.
//
// A press on a note or rest selects it when let go where it was pressed,
// even with a piece armed; a note dragged away lands where it is let go.
// With a piece armed, a press anywhere else shows and sounds it, and
// letting go places it.
//
// Server state arrives as data attributes on the hook element:
// data-geometry (EditorGeometry.encode), data-armed (EditorGeometry.armed),
// data-insert (Insert mode), data-mode, data-dirty, data-loading and
// data-layout. Playback is Editor.Transport's: it says where it is with
// "score:playhead" and "score:play-start" window events, and the playhead
// is drawn here (playhead_view.js).

import {sharedAudio} from "./audio"
import {Band} from "./band"
import {chordAt} from "./chord"
import {setPageCursor} from "./cursor"
import {locate, pitchOf} from "./geometry"
import {eventTarget, onOpeningTempo, tempoKind} from "./hits"
import {dialogOpen, keyId, typing} from "./keyboard"
import {aimNoteDrag, dragTargets, dropParams, endNoteDrag, startNoteDrag, tempoDropAt} from "./note_drag"
import {Overlay} from "./overlay"
import {PageGuard} from "./page_guard"
import {modifierOf, placeParams, placementAt, tickAt} from "./placing"
import {PlayheadView} from "./playhead_view"
import {StatusNotes} from "./status_notes"
// The editor's keys, this hook's, the palette's (Editor.Palette's
// .PaletteKeys) and the transport's (Editor.Transport's .Transport); the
// cheat-sheet (DrawMusicWeb.Shortcuts) lists the same ones.
import KEYS from "./keys.json"

// A pointer drag shorter than this (staff spaces) is a click.
const DRAG_THRESHOLD = 0.5
// Clicks on empty staff remember a paste position on this grid (a 16th).
const CLICK_GRID = 240
// Length of the tone played over each new line or space (seconds).
const PLACEMENT_TONE = 0.25
// ↑/↓: a scale step (Shift: an octave, Ctrl: a semitone); ←/→: a beat.
const ARROWS = {ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right"}

export default {
  mounted() {
    this.overlay = new Overlay(this.el.querySelector("#score-overlay"))
    this.band = new Band({
      el: this.el,
      overlay: this.overlay,
      geometry: () => this.geometry,
      send: (event, payload, reply) => this.pushEvent(event, payload, reply),
    })
    this.playhead = new PlayheadView(this.el, this.overlay)
    this.guard = new PageGuard(() => this.el.dataset.dirty === "true")
    this.notes = new StatusNotes()
    this.lastSound = null
    this.readState()
    this.listen()
    this.guard.attach()
  },

  updated() {
    this.readState()
    this.guard.sync()
  },

  destroyed() {
    for (const [target, type, fun, capture] of this.listeners) target.removeEventListener(type, fun, capture)
    this.guard.detach()
    setPageCursor(this.el, null)
  },

  // A press anywhere on the paper counts, margins included: a rubber band
  // is often started just above and left of the music.
  listen() {
    this.paper = this.el.closest("#score-paper") || this.el
    this.listeners = [
      [this.el, "pointermove", (e) => this.pointerMove(e)],
      [this.el, "pointerleave", () => this.pressing || this.overlay.clear()],
      [this.paper, "pointerdown", (e) => this.pointerDown(e)],
      [this.el, "pointerup", (e) => this.pointerUp(e)],
      [this.el, "pointercancel", () => this.cancelPress()],
      [this.el, "dblclick", (e) => this.doubleClick(e)],
      [window, "keydown", (e) => this.key(e)],
      [window, "contextmenu", (e) => this.contextMenu(e)],
      [window, "score:playhead", (e) => this.playhead.playing(e.detail)],
      [window, "score:play-start", (e) => this.playhead.waitAt(e.detail.tick)],
      [window, "score:redraw", (e) => this.notes.startRedrawing(e.detail.layout)],
    ]
    for (const [target, type, fun, capture] of this.listeners) target.addEventListener(type, fun, capture)
  },

  readState() {
    this.score = this.el.querySelector("#score")
    this.geometry = JSON.parse(this.el.dataset.geometry)
    this.armed = JSON.parse(this.el.dataset.armed || "null")
    this.mode = this.el.dataset.mode || "edit"
    this.insert = this.el.dataset.insert === "true"
    this.el.classList.toggle("play-mode", this.mode === "play")
    this.overlay.setViewBox(this.score.dataset.viewBox)
    setPageCursor(this.el, this.armed && this.armed.glyph)
    if (!this.armed && !this.drag) this.overlay.clear()
    this.playhead.update(this.geometry, this.mode)
    this.notes.update({loading: this.el.dataset.loading === "true", layout: this.el.dataset.layout})
  },

  // Where the armed piece would land under the pointer, or null.
  target(e) {
    return placementAt(this.geometry, this.armed, this.insert, this.overlay.toScore(e), modifierOf(e))
  },

  pointerMove(e) {
    if (this.tempoDrag) return this.moveTempoDrag(e)
    if (this.band.active) return this.band.drag(e)
    if (this.pending) return this.movePending(e)
    if (this.drag) return this.moveDrag(e)
    if (this.tieDrag) return this.overlay.guide(this.tieDrag.start.x, this.tieDrag.start.y, ...this.pointAt(e))
    this.hover(e)
  },

  pointAt(e) {
    const {x, y} = this.overlay.toScore(e)
    return [x, y]
  },

  // The ghost follows the pointer; it sounds only while the button is down.
  hover(e) {
    const t = this.target(e)
    if (!t) return this.overlay.clear()
    this.overlay.ghost(this.geometry, this.armed, t)

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
    // Anything else drawn over the paper (a dialog, its backdrop) keeps its
    // own presses: capturing the pointer would rob a drop list of its release.
    if (!this.el.contains(e.target)) return e.target === this.paper && this.startBand(e)

    const hit = eventTarget(e)
    // Play mode: a note sounds its chord; anywhere else starts a range selection.
    if (this.mode === "play" && hit) return hit.kind === "note" && this.pushEvent("audition", {id: hit.id})
    if (this.mode === "play") return this.startBand(e)
    if (this.armed && this.armed.kind === "tie") return hit && hit.kind === "note" && this.startTie(e, hit)
    if (this.armed && !hit) return this.startPress(e)
    if (!hit) return this.startBand(e)

    // A note, rest or tempo mark, armed or not: selected on release, unless
    // a note or tempo mark is dragged first. (A chord is stacked by pressing
    // another line or space at the note's start, which is not on the note.)
    this.pending = {hit, start: this.overlay.toScore(e), shift: e.shiftKey}
    this.el.setPointerCapture(e.pointerId)
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
    if (this.band.active) this.endBand()
  },

  // Double-clicking a tempo mark opens its dialog; the opening marking,
  // the score's settings. The press before it captured the pointer (for a
  // drag or a band), which sends the double-click to this element, not to
  // the mark: what was double-clicked is what lies under the pointer.
  doubleClick(e) {
    if (this.mode !== "edit") return
    const under = {target: document.elementFromPoint(e.clientX, e.clientY) || e.target}
    if (onOpeningTempo(under)) return this.pushEvent("open_settings", {})
    const hit = eventTarget(under)
    if (tempoKind(hit)) this.pushEvent("edit_tempo", {id: hit.id})
  },

  startBand(e) {
    this.band.start(this.overlay.toScore(e))
    this.el.setPointerCapture(e.pointerId)
  },

  // A click (no drag) on empty music clears the selection and remembers
  // where, for a paste; a drag selects the range it covers.
  endBand() {
    const {start, end} = this.band.finish()
    if (Math.hypot(end.x - start.x, end.y - start.y) < DRAG_THRESHOLD) {
      const at = tickAt(this.geometry, start)
      if (at !== null) this.pushEvent("set_last_click", {at: Math.floor(at / CLICK_GRID) * CLICK_GRID})
      return this.pushEvent("clear_selection", {})
    }

    const from = tickAt(this.geometry, start)
    const to = tickAt(this.geometry, end)
    if (from !== null && to !== null) this.pushEvent("select_range", {from: Math.round(from), to: Math.round(to)})
  },

  // Placing: the press sounds the armed piece, each new line or space
  // sounds while it is held, and letting go places it.
  startPress(e) {
    this.pressing = true
    this.lastSound = null
    this.el.setPointerCapture(e.pointerId)
    this.hover(e)
  },

  place(e) {
    const t = this.target(e)
    if (!t) return
    this.lastSound = null
    this.pushEvent("place", placeParams(t))
  },

  // A press on a note or tempo mark becomes a drag once the pointer has
  // moved far enough.
  movePending(e) {
    const {hit, start} = this.pending
    const point = this.overlay.toScore(e)
    if (Math.hypot(point.x - start.x, point.y - start.y) < DRAG_THRESHOLD) return
    if (tempoKind(hit)) {
      this.pending = null
      this.tempoDrag = {hit, start}
      return this.moveTempoDrag(e)
    }
    if (hit.kind !== "note") return
    this.pending = null
    this.drag = startNoteDrag(this.score, this.geometry, hit)
    this.moveDrag(e)
  },

  // Where the dragged notes would land, drawn and sounded on each change.
  moveDrag(e) {
    const modifier = modifierOf(e)
    if (!aimNoteDrag(this.drag, this.geometry, this.overlay.toScore(e), modifier)) return
    const targets = dragTargets(this.drag)
    this.overlay.draggedNotes(this.geometry, this.drag.anchor.system, targets, modifier)
    this.play(targets.map((t) => pitchOf(t.step, modifier, this.geometry.sf)))
  },

  // Lands the dragged notes. Let go where it started, the drag is a click.
  endDrag(e) {
    const drag = this.drag
    this.cancelDrag()
    const params = dropParams(drag)
    if (params) this.pushEvent("drop", params)
    else this.select({hit: drag.anchor, shift: e.shiftKey})
  },

  cancelDrag() {
    if (!this.drag) return
    endNoteDrag(this.drag)
    this.drag = null
    this.overlay.clear()
  },

  // A dragged tempo mark (or a rit.'s end) snaps to the nearest column; a
  // line shows where it would land.
  moveTempoDrag(e) {
    const spot = tempoDropAt(this.geometry, this.tempoDrag, this.overlay.toScore(e))
    if (!spot) return
    this.tempoDrag.tick = spot.tick
    this.overlay.tempoGuide(this.geometry, spot.system, spot.x)
  },

  endTempoDrag() {
    const {hit, tick} = this.tempoDrag
    this.tempoDrag = null
    this.overlay.clear()
    if (tick === undefined) return
    this.pushEvent(hit.kind === "tempo" ? "move_tempo" : "resize_tempo", {id: hit.id, tick})
  },

  // Tie tool: drag from one note to another.
  startTie(e, hit) {
    this.tieDrag = {from: hit.id, start: this.overlay.toScore(e)}
    this.el.setPointerCapture(e.pointerId)
  },

  endTie(e) {
    const {from} = this.tieDrag
    this.tieDrag = null
    this.overlay.clear()
    const under = document.elementFromPoint(e.clientX, e.clientY)
    const target = under && under.closest("[id^='note-']")
    if (target && target.id.slice(5) !== from) this.pushEvent("tie", {from, to: target.id.slice(5)})
  },

  // A click on a note, rest or tempo mark: Shift toggles it, else it alone is selected.
  select({hit, shift}) {
    this.pushEvent("select", {ids: [hit.id], add: shift})
  },

  // Abandons whatever the pointer was doing.
  cancelPress() {
    this.pending = null
    this.pressing = false
    this.tieDrag = null
    this.tempoDrag = null
    this.band.cancel()
    this.cancelDrag()
    this.overlay.clear()
  },

  // The score's keys, in Edit mode. The palette's (P, the lengths, R, ., T,
  // Insert, undo, redo and select all) are Editor.Palette's .PaletteKeys;
  // Play mode's (Space, Home, End, L, Esc) are Editor.Transport's .Transport.
  key(e) {
    if (typing(e) || dialogOpen()) return
    if (!KEYS.includes(keyId(e))) return
    const ctrl = e.ctrlKey || e.metaKey
    const k = e.key.toLowerCase()
    const send = (event, payload = {}) => {
      e.preventDefault()
      this.pushEvent(event, payload)
    }

    // Help works in both modes.
    const help = document.getElementById("help")
    if (e.key === "?" && help) {
      e.preventDefault()
      return this.js().exec(help.dataset.show)
    }
    if (this.mode === "play") return

    if (e.key === "Escape") {
      if (this.drag || this.pending) {
        e.preventDefault()
        return this.cancelPress()
      }
      this.pressing = false
      return send(this.armed ? "disarm" : "clear_selection")
    }

    if (ARROWS[e.key]) {
      const by = e.shiftKey ? "octave" : ctrl ? "semitone" : "step"
      return send("move", {dir: ARROWS[e.key], by})
    }

    if (ctrl && k === "c") return send("copy")
    if (ctrl && k === "x") return send("cut")
    if (ctrl && k === "v") return send("paste")
    if (ctrl || e.altKey) return
    if (e.key === "Delete" || e.key === "Backspace") return send("delete")
  },

  // Right-click: cancels placing or a drag; on the opening tempo marking,
  // the score's settings. Anywhere else in the music it asks for the menu:
  // the server picks it from the selection, else from what is under the
  // pointer (`id`, null off the notes).
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
    if (!this.el.contains(e.target)) return
    e.preventDefault()
    if (onOpeningTempo(e)) return this.pushEvent("open_settings", {})

    const hit = eventTarget(e)
    const point = this.overlay.toScore(e)
    const at = locate(this.geometry, point.x, point.y) || {}
    this.pushEvent("open_menu", {id: hit ? hit.id : null, x: e.clientX, y: e.clientY, step: at.step, staff: at.staff})
  },

  // The tone for placing and dragging, on the playback instrument: one
  // MIDI number, or a chord's, sounded together.
  play(midis) {
    sharedAudio().preview([midis].flat(), PLACEMENT_TONE)
  },
}
