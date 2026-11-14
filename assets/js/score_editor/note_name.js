// A note's name for the reading aids: its letter and accidental, like "G♯",
// with no octave. A natural sign shows only when the note would otherwise
// read sharp or flat (by the key, or an earlier accidental in the measure).
// Pure functions: no DOM.

const LETTERS = "CDEFGAB"
const SIGNS = {"-2": "𝄫", "-1": "♭", 1: "♯", 2: "𝄪"}

function mod(n, m) {
  return ((n % m) + m) % m
}

// `step`: the staff step (C4 is 28); `alter`: -2 to 2; `inEffect`: the
// alteration the step would have with no sign of its own.
export function noteName(step, alter, inEffect) {
  const letter = LETTERS[mod(step, 7)]
  if (alter !== 0) return `${letter}${SIGNS[alter]}`
  return inEffect === 0 ? letter : `${letter}♮`
}
