// A note's name for the reading aids: its letter, accidental and octave,
// like "G♯4" (middle C is "C4"). Pure functions: no DOM.

const LETTERS = "CDEFGAB"
const SIGNS = {"-2": "𝄫", "-1": "♭", 0: "", 1: "♯", 2: "𝄪"}

function mod(n, m) {
  return ((n % m) + m) % m
}

// `step`: the staff step (C4 is 28); `alter`: -2 to 2.
export function noteName(step, alter) {
  return `${LETTERS[mod(step, 7)]}${SIGNS[alter] ?? ""}${Math.floor(step / 7)}`
}
