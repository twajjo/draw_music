// Dragging notes up and down (to another pitch, or one note alone to the
// other staff) and tempo marks along the music. Plain functions over a
// drag's state; the hook draws and sends what they give.

import {keyAlter, locate, stepAtY, stepOnStaff, staffStepAt} from "./geometry"
import {nearestColumn} from "./hits"

// A moved note keeps its accidental (as Editing.move_steps): the key's
// version of its new letter, sharpened or flattened as much as it was.
function keptAlter(sf, note, step) {
  const accidental = note.alter - keyAlter(sf, note.step)
  return Math.max(-2, Math.min(2, keyAlter(sf, step) + accidental))
}

// The pressed note drags alone, or with the selection if it is selected.
// One note on its own may move to the other staff; several keep their
// staves. The originals are faded (`dragging`) meanwhile.
export function startNoteDrag(scoreEl, geometry, hit) {
  const pressed = document.getElementById(`note-${hit.id}`)
  const elements = pressed.classList.contains("selected")
    ? [...scoreEl.querySelectorAll(".selected[id^='note-']")]
    : [pressed]

  const notes = elements.map((el) => {
    const staff = el.dataset.staff
    const y = Number(el.getAttribute("y"))
    const system = geometry.systems[Number(el.closest("[data-system]").dataset.system)]
    const step = stepAtY(geometry, staff, y)
    const alter = el.dataset.alter === undefined ? keyAlter(geometry.sf, step) : Number(el.dataset.alter)
    return {el, id: el.id.slice(5), staff, step, alter, x: Number(el.getAttribute("x")), system}
  })

  const anchor = notes.find((note) => note.id === hit.id)
  elements.forEach((el) => el.classList.add("dragging"))
  // delta starts unset, so the first move draws and sounds the preview.
  return {notes, anchor, single: notes.length === 1, delta: null, staff: anchor.staff, modifier: null, sf: geometry.sf}
}

// Follows the pointer (`point`, in staff spaces). True when where the notes
// would land has changed, to draw and sound again.
export function aimNoteDrag(drag, geometry, point, modifier) {
  const {anchor} = drag
  const {staff, step} = drag.single
    ? staffStepAt(geometry, anchor.system, point.y)
    : {staff: anchor.staff, step: stepOnStaff(geometry, anchor.system, anchor.staff, point.y)}
  const delta = step - anchor.step

  if (delta === drag.delta && staff === drag.staff && modifier === drag.modifier) return false
  Object.assign(drag, {delta, staff, modifier})
  return true
}

// Each dragged note's landing place: its staff (the pointer's, for one
// note alone), step and alteration (a held key's, else its own kept).
export function dragTargets(drag) {
  const {notes, single, staff, delta, modifier, sf} = drag
  return notes.map((note) => {
    const step = note.step + delta
    const alter = modifier ?? keptAlter(sf, note, step)
    return {...note, staff: single ? staff : note.staff, step, alter}
  })
}

// The `drop` event's params, or null when the drag ended where it started
// (it was a click).
export function dropParams(drag) {
  const {single, staff, delta, modifier, anchor} = drag
  if (delta === 0 && staff === anchor.staff && modifier === null) return null

  const targets = dragTargets(drag)
  const ids = targets.map((t) => t.id)
  const params = single ? {ids, staff, step: targets[0].step} : {ids, steps: delta}
  if (modifier !== null) params.alter = modifier
  return params
}

// The originals stop being faded.
export function endNoteDrag(drag) {
  drag.notes.forEach((note) => note.el.classList.remove("dragging"))
}

// Where a dragged tempo mark (or a rit.'s end) would land: the nearest note
// or rest column, {tick, system, x}, or null off the music. A mark stops
// short of the opening beat, whose tempo is the score's settings.
export function tempoDropAt(geometry, tempoDrag, point) {
  const at = locate(geometry, point.x, tempoDrag.start.y)
  if (!at) return null
  const target = nearestColumn(at.measure, point.x, tempoDrag.hit.kind === "tempo")
  return {tick: at.measure.start_tick + target.offset, system: at.system, x: target.x}
}
