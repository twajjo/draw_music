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

  const ry = y - system.y
  const {staff_top: top, top_step: topStep} = geometry
  const gapMiddle = (top.treble + 4 + top.bass) / 2
  const staff = ry < gapMiddle ? "treble" : "bass"
  const rawStep = topStep[staff] - Math.round((ry - top[staff]) * 2)
  const step = Math.min(MAX_STEP, Math.max(MIN_STEP, rawStep))

  const measure = measureAt(system, x)
  const tick = (x - measure.content_x) / measure.scale
  const offset = Math.min(measure.capacity - 1, Math.max(0, tick))

  return {system, measure, offset, staff, step}
}

// The step at y on a given staff of a system (no switching staves), for
// dragging a note up and down.
export function stepOnStaff(geometry, system, staff, y) {
  const raw = geometry.top_step[staff] - Math.round((y - system.y - geometry.staff_top[staff]) * 2)
  return Math.min(MAX_STEP, Math.max(MIN_STEP, raw))
}

// The grid position at or before `offset`, leaving room for the value.
export function snap(offset, grid, capacity) {
  const latest = Math.max(0, Math.floor((capacity - grid) / grid) * grid)
  return Math.min(latest, Math.floor(offset / grid) * grid)
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
