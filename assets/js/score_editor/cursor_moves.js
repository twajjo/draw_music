// Where the arrow keys move the insertion cursor, with nothing selected,
// from the geometry the server sends (EditorGeometry). Pure functions: no
// DOM. Each returns the new tick, or null when the cursor can't go that way.
//
//   ← / →           to the previous or next place a note or rest starts,
//                   on either staff (the score's end counts as one)
//   Ctrl+← / Ctrl+→ to the previous or next bar line
//   ↑ / ↓           to the system above or below, at about the same place
//                   across the page (Page layout; Strip has one system)

import {insertColumn, locate, measureAt, offsetAt, staffItems} from "./geometry"
import {HEAD_WIDTH} from "./placing"
import {endTick, playheadAt} from "./playhead"

// Where a click on empty music at `point` (score coordinates) puts the
// cursor: in front of the next note or rest in that bar, on either staff,
// like a text cursor between letters, as placing in Insert mode does; past
// the bar's last one, at the start of the next bar (the space after a bar's
// last item is the next bar's). Null off the music.
export function cursorAt(geometry, point) {
  const at = locate(geometry, point.x, point.y)
  if (!at) return null

  const measure = at.measure
  const items = ["treble", "bass"]
    .flatMap((staff) => staffItems(geometry, measure, staff))
    .sort((a, b) => a.x - b.x)
  const next = insertColumn(items, point.x, HEAD_WIDTH)
  return measure.start_tick + (next ? next.offset : measure.capacity)
}

// The tick for an arrow `key` (ArrowLeft, ...) pressed with `ctrl`, from
// `tick`; null if it doesn't move.
export function cursorMove(geometry, tick, key, ctrl) {
  const back = key === "ArrowLeft" || key === "ArrowUp"
  if (key === "ArrowUp" || key === "ArrowDown") return ctrl ? null : lineStep(geometry, tick, back)
  return step(ctrl ? barLines(geometry) : stops(geometry), tick, back)
}

// Every bar line's tick, the score's end included, in order.
function barLines(geometry) {
  const starts = geometry.systems.flatMap((s) => s.measures.map((m) => m.start_tick))
  return [...starts, endTick(geometry)]
}

// The system above or below, at the cursor's place across the page, on the
// nearest place a note or rest starts there.
function lineStep(geometry, tick, back) {
  const at = playheadAt(geometry, tick)
  if (!at) return null
  const target = geometry.systems[geometry.systems.indexOf(at.system) + (back ? -1 : 1)]
  if (!target) return null

  const measure = measureAt(target, at.x)
  const offset = Math.min(Math.max(offsetAt(measure, at.x), 0), measure.capacity)
  const wanted = measure.start_tick + offset
  const nearest = (best, t) => (Math.abs(t - wanted) < Math.abs(best - wanted) ? t : best)
  return systemStops(target).reduce(nearest)
}

// The next tick in sorted `ticks` after `tick` (or the last before it,
// going `back`); null at the end.
function step(ticks, tick, back) {
  const found = back ? ticks.filter((t) => t < tick).pop() : ticks.find((t) => t > tick)
  return found ?? null
}

// Every place a note or rest starts, bar lines and the score's end
// included, in order and once each.
function stops(geometry) {
  const all = geometry.systems.flatMap(systemStops)
  return [...new Set([...all, endTick(geometry)])].sort((a, b) => a - b)
}

// The places a note or rest starts in one system, and its bar lines.
function systemStops(system) {
  return system.measures.flatMap((m) => [m.start_tick, ...m.columns.map((c) => m.start_tick + c.offset)])
}
