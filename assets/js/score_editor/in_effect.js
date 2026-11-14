// The alteration in effect at a point of the score, as Accidentals decides
// it on the server: the key's, overridden by the last earlier note on the
// same staff and step in the same measure. Read from the drawn noteheads.

import {keyAlter, measureAt, stepAtY} from "./geometry"

// `at`: {system, staff, step, x}; `skip`: ids of notes not to count (the
// ones being dragged).
export function alterInEffect(scoreEl, geometry, at, skip = []) {
  const {system, staff, step, x} = at
  const measure = measureAt(system, x)
  const index = geometry.systems.indexOf(system)
  const heads = scoreEl.querySelectorAll(`[data-system="${index}"] [id^='note-'][data-staff="${staff}"]`)

  let latest = null
  for (const el of heads) {
    const headX = Number(el.getAttribute("x"))
    const earlier = headX >= measure.x && headX < x && (!latest || headX > latest.x)
    if (earlier && !skip.includes(el.id.slice(5)) && stepAtY(geometry, staff, Number(el.getAttribute("y"))) === step) {
      const alter = el.dataset.alter === undefined ? keyAlter(geometry.sf, step) : Number(el.dataset.alter)
      latest = {x: headX, alter}
    }
  }
  return latest ? latest.alter : keyAlter(geometry.sf, step)
}
