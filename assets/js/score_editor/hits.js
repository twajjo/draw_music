// What a pointer event in the score is on: a note, rest or tempo mark, the
// opening tempo marking, the nearest column. DOM lookups and geometry only.

// The note, rest or tempo mark (and its id) under an event, if any. A
// tempo mark's label is "tempo"; a rit.'s or accel.'s end is "tempo-end".
export function eventTarget(e) {
  const el = e.target.closest && e.target.closest("[id^='note-'], [id^='rest-'], [id^='tempo-']")
  if (!el) return null
  if (el.id.startsWith("tempo-end-")) return {kind: "tempo-end", id: el.id.slice(10)}
  if (el.id.startsWith("tempo-")) return {kind: "tempo", id: el.id.slice(6)}
  return {kind: el.id.startsWith("note-") ? "note" : "rest", id: el.id.slice(5)}
}

// A tempo mark, or a rit.'s or accel.'s end.
export function tempoKind(hit) {
  return Boolean(hit) && (hit.kind === "tempo" || hit.kind === "tempo-end")
}

// The opening tempo marking is the score's settings: it opens them.
export function onOpeningTempo(e) {
  return Boolean(e.target.closest && e.target.closest("#opening-tempo"))
}

// The column (or the measure's end) whose x is nearest `x`: {offset, x}.
// With `afterOpening`, the score's opening beat (tick 0) isn't a spot.
export function nearestColumn(measure, x, afterOpening = false) {
  const ends = [{offset: 0, x: measure.content_x}, {offset: measure.capacity, x: measure.content_end}]
  const spots = [...measure.columns, ...ends].filter((spot) => !afterOpening || measure.start_tick + spot.offset > 0)
  return spots.reduce((best, spot) => (Math.abs(spot.x - x) < Math.abs(best.x - x) ? spot : best))
}
