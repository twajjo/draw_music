// Where the transport's skips land, while playing or paused. Pure
// functions: no DOM, no audio.

import {secondsAt, tickAt} from "./playhead"

// Skipping back within this long (s) of a measure's or line's start goes to
// the one before.
const BACK_GRACE = 0.75

// How many seconds into the span a skip lands, or null if nowhere. `starts`
// are the measures' (or lines') starts in ticks, `anchors` the span's
// (TempoMap.anchors), `position` how far into the span playback is.
// Forward: the next start inside the span. Back: the start of this one, or,
// just after it starts (BACK_GRACE), the one before, like a CD player; never
// before the span's start.
export function skipTarget(starts, anchors, position, back) {
  const now = tickAt(anchors, position)
  const first = anchors[0].tick
  const last = anchors[anchors.length - 1].tick
  const target = back
    ? (starts.filter((tick) => tick > first && secondsAt(anchors, tick) < position - BACK_GRACE).pop() ?? first)
    : starts.find((tick) => tick > now + 0.5)
  if (target === undefined || target >= last) return null
  return secondsAt(anchors, target)
}
