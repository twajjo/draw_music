// After the selection is moved up or down with the arrow keys, its notes
// are read back from the redrawn score, to sound them. (Their names, a
// reading aid, are drawn by the server beside every selected note.)

import {keyAlter, pitchOf, stepAtY} from "./geometry"

// The selected notes as drawn: {system, staff, step, alter, x} each.
function selectedNotes(scoreEl, geometry) {
  return [...scoreEl.querySelectorAll(".selected[id^='note-']")].map((el) => {
    const staff = el.dataset.staff
    const step = stepAtY(geometry, staff, Number(el.getAttribute("y")))
    const alter = el.dataset.alter === undefined ? keyAlter(geometry.sf, step) : Number(el.dataset.alter)
    const system = geometry.systems[Number(el.closest("[data-system]").dataset.system)]
    return {system, staff, step, alter, x: Number(el.getAttribute("x"))}
  })
}

// A chord's heads are this close (staff spaces): a second's other head sits
// beside the stem. Notes at different times are further apart.
const CHORD_SPREAD = 1.5

// Whether the notes are one note or one chord: all drawn at about the same x
// in the same system.
function oneChord(notes) {
  return notes.every((note) => note.system === notes[0].system && Math.abs(note.x - notes[0].x) < CHORD_SPREAD)
}

// The pitches to sound: only for one note or one chord (a range of notes
// moves silently).
export function movedMidis(scoreEl, geometry) {
  const notes = selectedNotes(scoreEl, geometry)
  return oneChord(notes) ? notes.map((note) => pitchOf(note.step, note.alter, geometry.sf)) : []
}
