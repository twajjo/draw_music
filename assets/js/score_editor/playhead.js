// Where the playback line goes, from the geometry the server sends
// (EditorGeometry). Pure functions: no DOM.

import {xAt} from "./geometry"

// The tick playback has reached `seconds` in, between the anchors the
// server sends ([{seconds, tick}], first at 0 s; see TempoMap.anchors).
export function tickAt(anchors, seconds) {
  const next = anchors.findIndex((a) => a.seconds > seconds)
  if (next === -1) return anchors[anchors.length - 1].tick
  if (next === 0) return anchors[0].tick
  const a = anchors[next - 1]
  const b = anchors[next]
  return a.tick + ((seconds - a.seconds) / (b.seconds - a.seconds)) * (b.tick - a.tick)
}

// The other way: how many seconds into the span playback reaches `tick`.
export function secondsAt(anchors, tick) {
  const next = anchors.findIndex((a) => a.tick > tick)
  if (next === -1) return anchors[anchors.length - 1].seconds
  if (next === 0) return anchors[0].seconds
  const a = anchors[next - 1]
  const b = anchors[next]
  return a.seconds + ((tick - a.tick) / (b.tick - a.tick)) * (b.seconds - a.seconds)
}

// {system, x} for a tick: in the measure holding it, spaced like its notes;
// past the last measure, at the score's end. Null without systems.
export function playheadAt(geometry, tick) {
  for (const system of geometry.systems) {
    const measure = system.measures.find((m) => tick >= m.start_tick && tick < m.start_tick + m.capacity)
    if (measure) return {system, x: xAt(measure, tick - measure.start_tick)}
  }

  const system = geometry.systems[geometry.systems.length - 1]
  if (!system) return null
  const measure = system.measures[system.measures.length - 1]
  return {system, x: xAt(measure, measure.capacity)}
}

// The line's top and bottom, relative to its system: the grand staff with a
// staff space to spare at each end.
export function playheadSpan(geometry) {
  return {top: geometry.staff_top.treble - 1, bottom: geometry.staff_top.bass + 5}
}
