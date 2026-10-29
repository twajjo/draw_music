// Pointer position (in the score's staff-space units) → musical position,
// from the geometry the server sends with every render (EditorGeometry).
// Pure functions: no DOM.

// Steps of A0 and C8: the piano's range.
export const MIN_STEP = 5
export const MAX_STEP = 56

const SEMITONES = [0, 2, 4, 5, 7, 9, 11]
const SHARP_ORDER = [3, 0, 4, 1, 5, 2, 6] // F C G D A E B
const FLAT_ORDER = [6, 2, 5, 1, 4, 0, 3] // B E A D G C F

const mod = (n, m) => ((n % m) + m) % m

// The system a y falls in: the one whose grand staff is closest.
function systemAt(geometry, y) {
  const bottom = geometry.staff_top.bass + 4
  let best = null
  for (const system of geometry.systems) {
    const distance = Math.abs(y - (system.y + bottom / 2))
    if (!best || distance < best.distance) best = {system, distance}
  }
  return best && best.system
}

function measureAt(system, x) {
  const measures = system.measures
  return (
    measures.find((m) => x >= m.x && x < m.x + m.width) ||
    (x < measures[0].x ? measures[0] : measures[measures.length - 1])
  )
}

// {system, measure, offset, staff, step} for a point, or null without
// systems. Between the staves, the closer staff wins.
export function locate(geometry, x, y) {
  const system = systemAt(geometry, y)
  if (!system) return null

  const {staff, step} = staffStepAt(geometry, system, y)
  const measure = measureAt(system, x)
  const offset = Math.min(measure.capacity - 1, Math.max(0, offsetAt(measure, x)))

  return {system, measure, offset, staff, step}
}

// A measure's linear stretches (as MeasureGeometry): each column to the
// start of the next column's insertion gap, the last to the content's end.
function segments(measure) {
  const {columns} = measure
  return columns.map((column, i) => {
    const next = columns[i + 1]
    const to = next ? {offset: next.offset, x: next.x - measure.gap} : {offset: measure.capacity, x: measure.content_end}
    return [column, to]
  })
}

// Ticks into the measure at x; in an insertion gap, the next column's offset.
export function offsetAt(measure, x) {
  const all = segments(measure)
  const [from, to] = all.find(([, end]) => x < end.x) || all[all.length - 1]
  if (x <= from.x) return from.offset
  return from.offset + ((x - from.x) / (to.x - from.x)) * (to.offset - from.offset)
}

// x of `offset` ticks into the measure.
export function xAt(measure, offset) {
  const all = segments(measure)
  const [from, to] = all.find(([, end]) => offset < end.offset) || all[all.length - 1]
  return from.x + ((offset - from.offset) / (to.offset - from.offset)) * (to.x - from.x)
}

// Overlay: the column on `staff` whose insertion gap or notehead (`head`
// wide) is at x, or null.
export function columnAt(measure, staff, x, head) {
  return measure.columns.find((c) => c.staves.includes(staff) && x >= c.x - measure.gap && x < c.x + head) || null
}

// Insert: the column on `staff` a click at x goes in front of (the first
// whose notehead ends right of x), or null past the last one.
export function insertColumn(measure, staff, x, head) {
  return measure.columns.find((c) => c.staves.includes(staff) && x < c.x + head) || null
}

// The staff and step at y in a given system; between the staves, the
// closer staff.
export function staffStepAt(geometry, system, y) {
  const top = geometry.staff_top
  const gapMiddle = (top.treble + 4 + top.bass) / 2
  const staff = y - system.y < gapMiddle ? "treble" : "bass"
  return {staff, step: stepOnStaff(geometry, system, staff, y)}
}

// The step at y on a given staff of a system (no switching staves), for
// dragging several notes up and down together.
export function stepOnStaff(geometry, system, staff, y) {
  const raw = geometry.top_step[staff] - Math.round((y - system.y - geometry.staff_top[staff]) * 2)
  return Math.min(MAX_STEP, Math.max(MIN_STEP, raw))
}

// The step a notehead drawn at y (relative to its system) sits on.
export function stepAtY(geometry, staff, y) {
  return geometry.top_step[staff] - Math.round((y - geometry.staff_top[staff]) * 2)
}

// The grid position nearest `offset`, leaving room for the value.
export function snap(offset, grid, capacity) {
  const latest = Math.max(0, Math.floor((capacity - grid) / grid) * grid)
  return Math.min(latest, Math.round(offset / grid) * grid)
}

// The alteration the key gives a step's letter.
export function keyAlter(sf, step) {
  const letter = mod(step, 7)
  if (sf > 0) return SHARP_ORDER.slice(0, sf).includes(letter) ? 1 : 0
  if (sf < 0) return FLAT_ORDER.slice(0, -sf).includes(letter) ? -1 : 0
  return 0
}

// MIDI number of a step with an alteration (null: the key's).
export function pitchOf(step, alter, sf) {
  const octave = Math.floor(step / 7)
  const natural = 12 * (octave + 1) + SEMITONES[mod(step, 7)]
  return natural + (alter ?? keyAlter(sf, step))
}

// y of a step on a staff, relative to its system.
export function stepY(geometry, staff, step) {
  return geometry.staff_top[staff] + (geometry.top_step[staff] - step) / 2
}

// Steps of the ledger lines a step needs on its staff.
export function ledgerSteps(geometry, staff, step) {
  const top = geometry.top_step[staff]
  const bottom = top - 8
  const steps = []
  for (let s = top + 2; s <= step; s += 2) steps.push(s)
  for (let s = bottom - 2; s >= step; s -= 2) steps.push(s)
  return steps
}
