// The armed chord at a pointer position, for the placement preview: its
// notes ({step, alter, midi}, lowest first) and its name ("Cm", "ii · Dm").
// The shape comes from the server (EditorGeometry.ChordShape). Pure
// functions: no DOM.

import {keyAlter, pitchOf} from "./geometry"

const LETTERS = "CDEFGAB"
const ACCIDENTAL_NAMES = {"-2": "𝄫", "-1": "♭", 0: "", 1: "♯", 2: "𝄪"}

const mod = (n, m) => ((n % m) + m) % m

// A quality is built on the pointer's note (with Shift/Ctrl, the palette's
// accidental, or the key's); a scale degree on its letter in the pointer's octave.
function tonesOf(shape, step, rootAlter, sf) {
  if (shape.kind === "quality") {
    const rootMidi = pitchOf(step, rootAlter, sf)
    return shape.tones.map(([steps, semitones]) => {
      const toneStep = step + steps
      const midi = rootMidi + semitones
      return {step: toneStep, alter: midi - pitchOf(toneStep, 0, sf), midi}
    })
  }

  const rootStep = Math.floor(step / 7) * 7 + shape.root_letter
  return shape.tones.map(([steps, alter]) => ({
    step: rootStep + steps,
    alter,
    midi: pitchOf(rootStep + steps, alter, sf),
  }))
}

function nameOf(shape, root) {
  const name = LETTERS[mod(root.step, 7)] + ACCIDENTAL_NAMES[root.alter] + shape.suffix
  return shape.numeral ? `${shape.numeral} · ${name}` : name
}

// null unless a chord is armed.
export function chordAt(armed, target, sf) {
  if (!armed || armed.kind !== "chord" || !armed.chord) return null
  const rootAlter = target.modifier ?? armed.alter ?? keyAlter(sf, target.step)
  const tones = tonesOf(armed.chord, target.step, rootAlter, sf)
  return {tones, label: nameOf(armed.chord, tones[0])}
}
