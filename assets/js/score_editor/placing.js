// Where the armed piece would land, from a point in the score's staff-space
// coordinates. Pure functions over the geometry (EditorGeometry.encode).

import {locate, snap, staffItems, xAt, columnAt, insertColumn} from "./geometry"

// About a notehead's width (staff spaces): a click this far right of a
// column is still on its note or rest.
export const HEAD_WIDTH = 1.3

// The accidental a held key adds: Shift sharpens, Ctrl or Alt flattens.
export function modifierOf(e) {
  if (e.shiftKey) return 1
  return e.ctrlKey || e.altKey ? -1 : null
}

// Where the armed piece would land, or null, and where its ghost goes
// (ghostX). Like a text editor: in Insert, the piece goes in front of the
// note or rest whose notehead ends right of the pointer, its ghost in that
// item's insertion gap. In Overlay, a note or rest's gap or head means its
// start; anywhere else the beat grid, and it types over the time it covers.
// In both, like a text cursor, white space belongs to the item to its right:
// the space after a staff's last item in a bar belongs to the next bar, so
// the piece goes at its start (`nextBar`) and nothing to the left changes.
// Items are hit where they're drawn (staffItems: a bar rest is centred).
export function placementAt(geometry, armed, insert, {x, y}, modifier) {
  if (!armed || !armed.glyph) return null
  const at = locate(geometry, x, y)
  if (!at) return null

  const {measure} = at
  const items = staffItems(geometry, measure, at.staff)
  if (pastLastItem(items, x)) return {...at, offset: 0, nextBar: true, ghostX: x, modifier}

  const gridded = snap(at.offset, armed.grid, measure.capacity)

  if (insert) {
    const column = insertColumn(items, x, HEAD_WIDTH)
    if (column) return {...at, offset: column.offset, ghostX: column.x - measure.gap / 2 - HEAD_WIDTH / 2, modifier}
    return {...at, offset: gridded, ghostX: xAt(measure, gridded), modifier}
  }

  const column = columnAt(items, measure.gap, x, HEAD_WIDTH)
  const offset = column ? column.offset : gridded
  return {...at, offset, ghostX: xAt(measure, offset), modifier}
}

// The `place` event's params for a placement. The bar after the last one
// is sent as is: the server adds it.
export function placeParams(t) {
  const measure = t.nextBar ? t.measure.index + 1 : t.measure.index
  const params = {measure, offset: t.offset, staff: t.staff, step: t.step}
  if (t.modifier !== null) params.alter = t.modifier
  return params
}

// Whether x is right of the staff's last item (staffItems) in the measure,
// past its head: in the white space that belongs to the next bar.
function pastLastItem(items, x) {
  const last = items[items.length - 1]
  return last !== undefined && x >= last.x + HEAD_WIDTH
}

// Absolute tick at a point (by x, in the system the point is in), or null.
export function tickAt(geometry, point) {
  const at = locate(geometry, point.x, point.y)
  return at && at.measure.start_tick + at.offset
}
