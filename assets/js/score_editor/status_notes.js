// The notes shown while the score isn't on screen yet: "Loading the
// score…" when the editor opens, and "Redrawing the music…" after a change
// of layout. Each goes once the browser has painted the score.

// After the next paint: two frames, as the first runs before it.
function afterPaint(fun) {
  requestAnimationFrame(() => requestAnimationFrame(fun))
}

export class StatusNotes {
  constructor() {
    this.redrawTo = null
  }

  // A new layout was picked ("score:redraw"): the note is up until the
  // score has arrived in that layout.
  startRedrawing(layout) {
    this.redrawTo = layout
    document.getElementById("score-redrawing").hidden = false
  }

  // Each update: `loading` (the score hasn't arrived) and the `layout` it's in.
  update({loading, layout}) {
    this.showLoading(loading)
    this.showRedrawing(layout)
  }

  // Once the score has arrived, the loading note says it's being drawn and
  // goes once the browser has painted it (a long score takes a while), so
  // the paper never looks empty.
  showLoading(loading) {
    const note = document.getElementById("score-loading")
    if (!note || note.hidden || loading) return
    document.getElementById("score-loading-text").textContent = "Drawing the score…"
    afterPaint(() => (note.hidden = true))
  }

  showRedrawing(layout) {
    if (!this.redrawTo || layout !== this.redrawTo) return
    this.redrawTo = null
    const note = document.getElementById("score-redrawing")
    afterPaint(() => (note.hidden = true))
  }
}
