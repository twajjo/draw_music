// Overlay's placement zones (plans/overlay-zones.md): a bar is divided
// into the places the armed item can start, `grid` ticks apart (the
// server's Context.zone_ticks), and a click lands on the start of the zone
// under the pointer. Pure functions over the geometry (EditorGeometry.encode).

import {xAt} from "./geometry"

// The start of the zone `offset` falls in.
export function zoneAt(measure, grid, offset) {
  const last = Math.floor((measure.capacity - 1) / grid) * grid
  return Math.min(last, Math.floor(offset / grid) * grid)
}

// The bar's zones as {offset, x0, x1, shaded}, left to right, alternately
// shaded and unshaded like the lines of a report.
export function zones(measure, grid) {
  const result = []
  for (let offset = 0, i = 0; offset < measure.capacity; offset += grid, i++) {
    const x0 = i === 0 ? measure.x : boundaryX(measure, offset)
    const x1 = edgeX(measure, offset + grid)
    result.push({offset, x0, x1, shaded: i % 2 === 0})
  }
  return result
}

// The stretches the armed item would cover from `offset` in `measure`,
// `ticks` long, as {measure, x0, x1}: in its bar and, for an item running
// past the bar line (tied over it), on into the bars after it.
export function coverage(geometry, measure, offset, ticks) {
  const spans = []
  let bar = measure
  let from = offset
  let left = ticks

  while (bar && left > 0) {
    const to = from + left
    spans.push({measure: bar, x0: from === 0 ? bar.x : boundaryX(bar, from), x1: edgeX(bar, to)})
    left = to - bar.capacity
    bar = nextMeasure(geometry, bar)
    from = 0
  }
  return spans
}

// Where a click starts counting as `offset`: an item's insertion gap
// belongs to the item, so at an item it is the start of its gap.
function boundaryX(measure, offset) {
  const column = measure.columns.find((c) => c.offset === offset)
  return column ? column.x - measure.gap : xAt(measure, offset)
}

// The right edge of a zone or span ending at `offset`: the bar line once
// it reaches the bar's end.
function edgeX(measure, offset) {
  return offset >= measure.capacity ? measure.x + measure.width : boundaryX(measure, offset)
}

// The measure after `measure` (by index), in its system or the next, or null.
function nextMeasure(geometry, measure) {
  for (const system of geometry.systems) {
    const next = system.measures.find((m) => m.index === measure.index + 1)
    if (next) return next
  }
  return null
}
