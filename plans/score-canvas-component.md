# PR 11: `Editor.ScoreCanvas`, in two parts

Step 11 of `plans/reexamine-all-components-and-sunny-pebble.md`. The score (the
`#score-editor` element, its overlay and the measure controls) and its hook
(`assets/js/score_editor/index.js`, 961 lines, the external `ScoreEditor`
hook) become a standalone LiveComponent with a short colocated hook. About 25
events leave `EditorLive`.

Done in one go, that would be about 20 files and a component well over 500
lines. So it comes in two PRs.

## 11a: split `index.js` into libraries (refactor only, no behaviour change)
`index.js` stays the external hook, but it becomes glue. Its parts move into
modules with no LiveView in them, each with one job:

| Module | What it holds | From `index.js` |
|---|---|---|
| `hits.js` | what a pointer event is on (a note, rest or tempo mark, the opening tempo), the nearest column | `eventTarget`, `tempoKind`, `onOpeningTempo`, `nearestColumn` |
| `placing.js` | where the armed piece would land, in Insert and Overlay (pure) | `target` |
| `overlay.js` | drawing on the overlay: the ghost, a chord, dragged notes, the band, the tie and tempo lines, clearing | `drawGhost`, `drawChord`, `drawDrag`, `glyph`, `clearGhost`, the band's rects |
| `band.js` | the selection band: dragging, scrolling at the view's edge, the preview of what it selects | `startBand`, `dragBand`, `autoScrollBand`, `drawBandTo`, `previewBand`, `lightBand`, `endPreview`, `edgeSpeed` |
| `note_drag.js` | dragging notes and tempo marks | `startDrag`, `moveDrag`, `dragTargets`, `endDrag`, `cancelDrag`, the tempo drag |
| `playhead_view.js` | drawing the playhead and following it | `showPlayhead`, `showIdlePlayhead`, `drawPlayhead`, `followPlayhead` |
| `page_guard.js` | the unsaved-changes guard (leaving, Back, links) | `dirty`, `syncGuard`, the `beforeunload`/`popstate`/link listeners |
| `status_notes.js` | "Loading the score…" and "Redrawing the music…" | `showLoading`, `startRedrawing`, `showRedrawing` |
| `cursor.js` (exists) | gains the page cursor while armed | `setPageCursor` |

The modules get what they need passed in (the overlay element, the
geometry, a `send(event, payload)` function), never the hook itself, so 11b
can use them unchanged. `index.js` keeps only the lifecycle, the pointer
dispatch (down/move/up/leave), the keys and the right-click. Target: under
250 lines.

**Checks:** `mix precommit` (no Elixir changes), the bundle builds, and you
try every pointer action in the browser: placing, chords, dragging notes and
tempo marks, the tie tool, the band (with edge scrolling), right-click, the
playhead in both layouts, the loading and redrawing notes, and the
unsaved-changes guard.

## 11b: `Editor.ScoreCanvas` LiveComponent + `.ScoreCanvas` colocated hook
**Renders:** `#score-editor` with the score, the overlay and the measure
controls. The loading and redrawing notes move inside it, so the hook doesn't
reach outside its own element. The colocated `.ScoreCanvas` hook is 11a's
`index.js` glue, sending with `pushEventTo(this.el, …)`. `index.js` and the
external hook in `app.js` are deleted.

**Inputs:** `score`, `ctx`, `selection`, `clipboard`, `engraved`, `pieces`,
`geometry_json`, `armed`, `insert?`, `editor_mode`, `layout`, `loading?`,
`dirty?`.

**Owns:** `last_click` (where a click on empty staff puts the next paste),
which leaves `EditorLive`.

**Events it handles** (all leave `EditorLive`):
- selecting: `select`, `select_range`, `preview_range` (with a reply),
  `clear_selection`, `set_last_click`;
- editing: `place`, `drop`, `tie`, `move`, `delete`, `copy`, `cut`, `paste`,
  `insert_measure`, `delete_measure`, `add_measure`;
- tempo: `edit_tempo`, `move_tempo`, `resize_tempo`;
- the rest: `open_menu`, `audition`, `disarm`, `open_settings`.

Play mode ignores the editing ones, as `EditorLive` does today.

**What it reports** (all intents that already exist):
- `{:edit, fun}` and `{:edit, fun, :select}`;
- `{:session, fun}`: selection and clipboard;
- `{:open, {:menu, menu}}`, `{:open, {:tempo, target}}`, `{:open, :settings}`;
- `{:palette, %{armed: nil}}`: disarm;
- `{:flash, …}`: a malformed placement.

**Stays in `EditorLive`:**
- the unsaved-changes guard, as a small colocated `.UnsavedGuard` hook (it
  belongs to the page, not the score);
- `audition`'s push. Its sound goes to the transport's engine; the
  component pushes it.

**Tests:** about 80 `render_hook(view, "select" | "move" | …)` calls in 8 files,
and `EditorHelpers.place/5`, now target `#score-editor`. This change is
mechanical. New `score_canvas_test.exs` in `ComponentHostLive`: placing reports
an edit, a click selects, a band previews and selects, right-click opens the
menu, paste goes where the last click was, and Play mode ignores the edits.

**Split (agreed):** 11b moves selecting, tempo, `open_menu`, `audition`,
`disarm` and `open_settings`. Meanwhile the hook still pushes the editing
events (`place`, `drop`, `tie`, `move`, `delete`, `copy`, `cut`, `paste`, the
measure events) to the LiveView with `pushEvent`, as 9b did with `disarm`.
`last_click` stays in `EditorLive` until paste moves.

## 11c: the editing events move into `Editor.ScoreCanvas`
`place`, `drop`, `tie`, `move`, `delete`, `copy`, `cut`, `paste`,
`insert_measure`, `delete_measure` and `add_measure` leave `EditorLive`, with
`last_click`. The hook sends everything with `pushEventTo(this.el, …)`, and
their tests target `#score-editor`.

## Afterwards
PR 12 composes `EditorLive.render/1` and groups the leftover assigns, and
PR 13 is the function-order sweep. (`transport.ex`, at 578 lines, can be split
there too.)
