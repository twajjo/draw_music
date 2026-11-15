// After the selection is moved up or down with the arrow keys, its notes
// are read back from the redrawn score, to sound them and (a reading aid)
// name them.

import {alterInEffect} from "./in_effect"
import {keyAlter, pitchOf, stepAtY} from "./geometry"
import {noteName} from "./note_name"

// The selected notes as drawn: {system, staff, step, alter, x, y} each.
function selectedNotes(scoreEl, geometry) {
  return [...scoreEl.querySelectorAll(".selected[id^='note-']")].map((el) => {
    const staff = el.dataset.staff
    const y = Number(el.getAttribute("y"))
    const step = stepAtY(geometry, staff, y)
    const alter = el.dataset.alter === undefined ? keyAlter(geometry.sf, step) : Number(el.dataset.alter)
    const system = geometry.systems[Number(el.closest("[data-system]").dataset.system)]
    return {system, staff, step, alter, x: Number(el.getAttribute("x")), y}
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

// {midis, labels}: the pitches to sound (only for one note or one chord; a
// range of notes moves silently), and when `named`, a label
// ({system, x, y, name}) for each note.
export function movedNotes(scoreEl, geometry, named) {
  const notes = selectedNotes(scoreEl, geometry)
  const midis = oneChord(notes) ? notes.map((note) => pitchOf(note.step, note.alter, geometry.sf)) : []
  const labels = named
    ? notes.map((note) => ({...note, name: noteName(note.step, note.alter, alterInEffect(scoreEl, geometry, note))}))
    : []
  return {midis, labels}
}
