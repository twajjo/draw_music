// Drawing on the score's overlay (an <svg> over the score, in staff-space
// coordinates): the armed piece's ghost, a chord, dragged notes, the
// selection band and the guide lines of the tie and tempo drags. The
// playhead (class "playhead") is drawn there too, by playhead_view.js, and
// clearing leaves it.

import {keyAlter, ledgerSteps, stepY} from "./geometry"
import {chordAt} from "./chord"
import {playheadSpan} from "./playhead"

const SVG = "http://www.w3.org/2000/svg"
const ACCIDENTALS = {"-2": "", "-1": "", 0: "", 1: "", 2: ""}
// Chord preview (staff spaces): a second's upper note sits this far right;
// the name sits this far above the top note, at this size.
const SECOND_OFFSET = 1.2
const CHORD_LABEL_GAP = 2
const CHORD_LABEL_SIZE = 1.6
// A note's name (a reading aid) sits this far right of its head, at this size.
const NAME_GAP = 2.2
const NAME_SIZE = 1.6
// A band's highlight reaches this far (staff spaces) above and below the
// grand staff; a staff is four spaces tall.
const BAND_PAD = 1.5
const STAFF_SPACES = 4

function element(name, attributes) {
  const el = document.createElementNS(SVG, name)
  Object.entries(attributes).forEach(([k, v]) => el.setAttribute(k, v))
  return el
}

function glyph(char, x, y) {
  const text = element("text", {x, y, "font-family": "Bravura", "font-size": 4})
  text.textContent = char
  return text
}

function ledgerLines(g, geometry, staff, step, x) {
  for (const ledger of ledgerSteps(geometry, staff, step)) {
    const ly = stepY(geometry, staff, ledger)
    g.appendChild(element("line", {x1: x - 0.4, x2: x + 1.6, y1: ly, y2: ly, stroke: "currentColor", "stroke-width": 0.16}))
  }
}

// A note's name ("G♯4") beside its head at (x, y).
function nameLabel(x, y, name) {
  const text = element("text", {x: x + NAME_GAP, y: y + NAME_SIZE / 3, "font-family": "sans-serif", "font-size": NAME_SIZE})
  text.textContent = name
  return text
}

// A group in a system's coordinates, drawn faded in the score's ink.
function ghostGroup(systemY) {
  const g = element("g", {transform: `translate(0 ${systemY})`, fill: "currentColor", opacity: "0.6"})
  g.style.color = "var(--score-ink)"
  return g
}

function clamp(x, low, high) {
  return Math.min(high, Math.max(low, x))
}

export class Overlay {
  constructor(svg) {
    this.svg = svg
  }

  setViewBox(viewBox) {
    this.svg.setAttribute("viewBox", viewBox)
  }

  // Pointer → staff-space coordinates of the score's viewBox. The score is
  // drawn in pieces; the overlay spans them all with the whole viewBox.
  toScore(e) {
    const point = this.svg.createSVGPoint()
    point.x = e.clientX
    point.y = e.clientY
    return point.matrixTransform(this.svg.getScreenCTM().inverse())
  }

  // Empties it, all but the playhead.
  clear() {
    for (const child of [...this.svg.children]) if (!child.classList.contains("playhead")) child.remove()
  }

  // The armed piece drawn where it would land (`t`, from placementAt), with
  // ledger lines and the accidental a modifier adds, and `name` beside a
  // note if given; a chord's notes (and its name), if one is armed.
  ghost(geometry, armed, t, name = null) {
    this.clear()
    const g = ghostGroup(t.system.y)
    const x = t.ghostX
    const chord = chordAt(armed, t, geometry.sf)
    if (chord) {
      drawChord(g, geometry, armed, t, x, chord)
      return this.svg.appendChild(g)
    }

    const rest = armed.kind === "rest"
    const y = rest ? stepY(geometry, t.staff, geometry.top_step[t.staff] - 4) : stepY(geometry, t.staff, t.step)

    if (!rest) {
      ledgerLines(g, geometry, t.staff, t.step, x)
      const alter = t.modifier ?? armed.alter
      if (alter !== null && alter !== undefined) g.appendChild(glyph(ACCIDENTALS[alter], x - 1.3, y))
    }

    g.appendChild(glyph(armed.glyph, x, y))
    if (name && !rest) g.appendChild(nameLabel(x, y, name))
    this.svg.appendChild(g)
  }

  // Dragged notes' heads where they would land (`targets`, in `system`),
  // with their ledger lines and any accidental they'd have against the key;
  // `named` (a target) gets its name beside it.
  draggedNotes(geometry, system, targets, named = null) {
    this.clear()
    const g = ghostGroup(system.y)

    for (const t of targets) {
      const y = stepY(geometry, t.staff, t.step)
      ledgerLines(g, geometry, t.staff, t.step, t.x)
      if (t.alter !== keyAlter(geometry.sf, t.step)) g.appendChild(glyph(ACCIDENTALS[t.alter], t.x - 1.3, y))
      g.appendChild(glyph(t.el.textContent, t.x, y))
      if (named && t.id === named.id) g.appendChild(nameLabel(t.x, y, named.name))
    }
    this.svg.appendChild(g)
  }

  // A dashed guide line, from a tie's start to the pointer.
  guide(x1, y1, x2, y2) {
    this.clear()
    const dashes = {stroke: "var(--score-selection)", "stroke-width": 0.2, "stroke-dasharray": "0.5 0.3"}
    this.svg.appendChild(element("line", {x1, y1, x2, y2, ...dashes}))
  }

  // Where a dragged tempo mark would land: a dashed line down `system` at `x`.
  tempoGuide(geometry, system, x) {
    const {top, bottom} = playheadSpan(geometry)
    this.guide(x, system.y + top - 2, x, system.y + bottom)
  }

  // The band, drawn like a text selection: from `first` ({at, x}) to the
  // end of its line, whole lines between, and the last line up to `last`.
  band(geometry, first, last) {
    this.clear()
    const systems = geometry.systems
    const from = systems.indexOf(first.at.system)
    const to = systems.indexOf(last.at.system)
    const top = geometry.staff_top.treble - BAND_PAD
    const bottom = geometry.staff_top.bass + STAFF_SPACES + BAND_PAD

    for (let i = from; i <= to; i++) {
      const system = systems[i]
      const measures = system.measures
      const lineStart = measures[0].x
      const lineEnd = measures[measures.length - 1].x + measures[measures.length - 1].width
      const x0 = i === from ? clamp(first.x, lineStart, lineEnd) : lineStart
      const x1 = i === to ? clamp(last.x, lineStart, lineEnd) : lineEnd
      this.svg.appendChild(
        element("rect", {
          x: x0,
          y: system.y + top,
          width: Math.max(0, x1 - x0),
          height: bottom - top,
          fill: "var(--score-selection)",
          "fill-opacity": 0.12,
          stroke: "var(--score-selection)",
          "stroke-width": 0.1,
        }),
      )
    }
  }
}

// A chord's noteheads where they'll land: ledger lines, the accidentals
// the key doesn't already give, a second's upper note set off to the
// right, and the chord's name above it.
function drawChord(g, geometry, armed, t, x, chord) {
  let previous = null
  let top = Infinity

  for (const tone of chord.tones) {
    const y = stepY(geometry, t.staff, tone.step)
    const nx = previous !== null && tone.step - previous.step === 1 && !previous.shifted ? x + SECOND_OFFSET : x
    previous = {step: tone.step, shifted: nx !== x}
    top = Math.min(top, y)

    ledgerLines(g, geometry, t.staff, tone.step, nx)
    if (tone.alter !== keyAlter(geometry.sf, tone.step)) g.appendChild(glyph(ACCIDENTALS[tone.alter], x - 1.3, y))
    g.appendChild(glyph(armed.glyph, nx, y))
  }

  const label = element("text", {x, y: top - CHORD_LABEL_GAP, "font-family": "sans-serif", "font-size": CHORD_LABEL_SIZE})
  label.textContent = chord.label
  g.appendChild(label)
}
