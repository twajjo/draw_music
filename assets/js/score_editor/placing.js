// Where the armed piece would land, from a point in the score's staff-space
// coordinates. Pure functions over the geometry (EditorGeometry.encode).

import {locate, snap, xAt, columnAt, insertColumn} from "./geometry"

// About a notehead's width (staff spaces): a click this far right of a
// column is still on its note or rest.
const HEAD_WIDTH = 1.3

// The accidental a held key adds: Shift sharpens, Ctrl or Alt flattens.
export function modifierOf(e) {
  if (e.shiftKey) return 1
  return e.ctrlKey || e.altKey ? -1 : null
}

// Where the armed piece would land, or null, and where its ghost goes
// (ghostX). Like a text editor: in Insert, the piece goes in front of the
// note or rest whose notehead ends right of the pointer, its ghost in that
// item's insertion gap; past a bar's last item it follows the music. In
// Overlay, a note or rest's gap or head means its start; anywhere else the
// beat grid, and it types over the time it covers.
export function placementAt(geometry, armed, insert, {x, y}, modifier) {
  if (!armed || !armed.glyph) return null
  const at = locate(geometry, x, y)
  if (!at) return null

  const {measure} = at
  const gridded = snap(at.offset, armed.grid, measure.capacity)

  if (insert) {
    const column = insertColumn(measure, at.staff, x, HEAD_WIDTH)
    if (column) return {...at, offset: column.offset, ghostX: column.x - measure.gap / 2 - HEAD_WIDTH / 2, modifier}
    return {...at, offset: gridded, ghostX: xAt(measure, gridded), modifier}
  }

  const column = columnAt(measure, at.staff, x, HEAD_WIDTH)
  const offset = column ? column.offset : gridded
  return {...at, offset, ghostX: xAt(measure, offset), modifier}
}

// The `place` event's params for a placement.
export function placeParams(t) {
  const params = {measure: t.measure.index, offset: t.offset, staff: t.staff, step: t.step}
  if (t.modifier !== null) params.alter = t.modifier
  return params
}

// Absolute tick at a point (by x, in the system the point is in), or null.
export function tickAt(geometry, point) {
  const at = locate(geometry, point.x, point.y)
  return at && at.measure.start_tick + at.offset
}
