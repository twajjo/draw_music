# Phase 4: Editing

## Context
Phases 1–3 store compositions and draw scores read-only (Strip or Page
layout, SVG export). The main page is an unsaved Untitled draft. Phase 4
makes the score editable with the mouse and keyboard: a palette of notes
and rests, placing with hover tones, selection, moving, ties, chords,
measures, undo, saving, and score settings. Playback (Play mode) stays in
Phase 5.

The domain logic is already built and tested in Phase 2 (`Editing`,
`Timeline`, `Chords`, `Transpose`); Phase 4 adds a few `Editing`
functions, an editing session in `EditorLive`, the palette components and
a browser hook.

## Decisions (2026-10-22)
- **Architecture:** the server owns the score. `EditorLive` holds the
  session, and every change is an `Editing` call. A JS hook handles only
  what must be instant: pointer → (measure, tick, staff, step) mapping, the
  cursor glyph, hover tones, rubber band and drag previews. It sends
  semantic events.
- **Palette:** a slim sticky toolbar above the score.
- **Placement is one-shot:** after a placement the item is disarmed and the
  normal pointer returns. **Double-click** a palette item to lock it for
  repeated placements. **Esc** or **right-click** cancels.
- **Snap:** horizontally to the chosen value's grid (a dotted value snaps
  to its undotted grid). Vertically to the nearest line or space.
- **Cursor:** while an item is armed, the cursor *is* the item:
  - over the score, the system pointer is hidden and the glyph is drawn
    snapped to where it will land;
  - elsewhere, a small CSS cursor image of the glyph, drawn by the hook
    with Bravura on a canvas.
- **Undo/redo:** for the session (back to when the score was opened),
  kept in the LiveView and cleared on reload.
- **Insert mode** shifts **only the clicked staff**.
- **Audio:** Tone.js, already planned for Phase 5, is used now for hover
  tones.

## Domain additions: `DrawMusic.Music.Editing`
Each is pure and returns `{:ok, score, ...}` or `{:error, reason}`, like
the existing functions.
- **`insert_time(score, ctx, at, ticks, staff)`:** moves every event on
  `staff` starting at or after absolute tick `at` right by `ticks`.
  - A note sounding across `at` is split there; its tail moves, and the tie
    between the halves is dropped since they no longer touch.
  - It re-bars, appending bars as needed. The other staff is untouched.
- **`split(score, ctx, id)`:** a note or rest becomes two of half its
  length (dotted quarter → quarter + eighth; quarter → two eighths). Notes
  are tied; rests stay separate. `{:error, :unrepresentable}` for a 64th.
- **`set_value(score, ctx, id, value, dots)`:** changes an event's length
  in place. It is rejected with `:measure_full` or `:overlap` when it no
  longer fits, unless the caller has made room with `insert_time` first.
- **`delete(score, ctx, ids)`** (added 2026-10-22): removes the events and
  **closes the gap** on each staff they were on. Each later event on that
  staff moves left by the emptied time before it. Time still covered by
  another voice is not a gap. Used by Delete, Cut and the menu.
- **`transpose_chromatic(score, ctx, ids, semitones)`** (added): moves by
  half steps, re-spelled to suit the key (`Pitch.spell`).
- **`transpose_interval(score, ctx, ids, steps, semitones)`** (added):
  moves by an exact interval (e.g. a major third up = 2 steps, 4
  semitones). The letter moves by `steps` and the alteration makes up the
  semitones, re-spelled if that would need more than a double sharp or flat.
- **`reverse(score, ctx, ids)`** (added): plays the selection backwards in
  its own time span. Ties inside the selection are flipped to point forward;
  ties into or out of it are dropped.
- **`to_rest(score, ctx, id)` and `to_note(score, ctx, id, step, alter)`:**
  switch a note to a rest and back (the note side takes a pitch). Ties
  into or out of a note that becomes a rest are removed.

## Session: `DrawMusicWeb.EditorLive`
- **Assigns:**
  - `score` and `ctx` (from the version, or the draft defaults);
  - `selection` (MapSet of event ids);
  - `armed` (`nil` or `%{kind: :note | :rest | :chord | :tie, value, dots, alter, chord, locked?}`);
  - `insert?` (Insert vs Overwrite);
  - `undo` and `redo` (lists of earlier scores, newest first);
  - `dirty?`;
  - `engraved` (the layout, recomputed after each change);
  - `clipboard`;
  - `last_click` (where Ctrl+V pastes).
- **Applying an edit:** each edit runs through one helper, `apply_edit(socket, fun)`.
  - On `{:ok, score, ...}` it pushes the old score onto `undo`, clears `redo`, sets `dirty?`, re-engraves and pushes the new geometry to the hook.
  - On `{:error, reason}` it leaves everything as is and shows a short message, such as "That bar is full".
- **Events from the palette** (`phx-click`):
  - `arm` / `lock` / `disarm`;
  - `toggle_dot` / `set_accidental` (these modify the armed item, or the selection when nothing is armed);
  - `toggle_insert`, `undo`, `redo`, `add_measure`;
  - the save actions;
  - opening the settings panel.
- **Events from the hook** (`pushEvent`):
  - placing: `place` `%{measure, offset, staff, step, alter}`;
  - selecting: `select` `%{ids, add?}`, `select_range` `%{from, to}`, `clear_selection`;
  - moving: `drop` `%{ids, steps, alter}` (a pick-up released), `move` `%{dir}` (arrow keys);
  - editing: `tie` `%{from, to}`, `delete`, `copy`, `cut`, `paste`;
  - history: `undo`, `redo`;
  - context-menu actions: `split`, `set_value`, `to_rest`, `to_note`, `untie`;
  - measures: `insert_measure` / `delete_measure` `%{index}`.
- **To the hook** (`push_event` and data attributes on the hook element):
  - the engraved geometry: per system, `y` and the measure geometries (`x`, `width`, `start_tick`, `capacity`, `content_x`, `scale`);
  - the staff top y values and the step range;
  - the armed item, as glyph name and character;
  - the selection ids;
  - the key signature, for hover-tone pitches.

## Interactions
- **Placing:**
  - The click gives the measure, tick (snapped to the armed value's grid)
    and staff/step (in the gap between staves, the closer staff).
  - Shift = sharp, Ctrl/Alt = flat; otherwise the key's version of the
    letter.
  - Rests go on the clicked staff.
  - No voice is given, so the event goes in the lowest voice it fits.
  - In Insert mode the server first calls `insert_time` on that staff with
    the item's length.
  - On error, the item stays armed.
- **Hover tones:** a brief tone each time the snapped position reaches a new
  line or space, at the pitch a click would place (including Shift/Ctrl).
  Tone.js is started on the first user gesture, as browsers require.
- **Chords:**
  - The Chords menu arms a root-position quality (maj, min, dim, aug, 7,
    maj7, m7, m7♭5, dim7, sus2, sus4, add9) or a diatonic triad (I–vii°).
  - For a quality, the click sets the root's pitch. For a numeral, the
    click picks the octave.
  - It is one `place_chord` call at the armed value.
- **Selection** (nothing armed):
  - **Shift-click** a note or rest to add or remove it.
  - **Drag** on empty staff draws a rubber band across both staves (`select_range` by time).
  - **Left-click a rest** selects it (alone). A rest has no pitch to pick up.
  - Selected events are drawn in the selection color.
  - **Esc** clears the selection.
- **Pick-up (change pitch):**
  - With nothing armed, a **left-click** on a note lifts it, together with the rest of the selection if the note is selected.
  - The lifted notes follow the pointer by scale steps, playing tones. Shift or Ctrl/Alt shows ♯/♭.
  - A second left-click drops them (`drop` → `move_steps` plus `set_alter` if an accidental was added).
  - **Esc** or **right-click** returns them unchanged.
- **Keyboard:**
  - **Moving the selection:** ↑/↓ one scale step, ←/→ one beat.
  - **Editing:** Delete or Backspace removes; Ctrl+C/X/V copy, cut and paste (paste goes at `last_click`, else straight after the selection).
    Paste **always inserts** (decided 2026-10-22): it first calls
    `insert_time` with the clipboard's length on each staff the clipboard
    has events on, so existing music there moves right. This holds in
    Overwrite mode too.
  - **History:** Ctrl+Z undoes; Ctrl+Shift+Z or Ctrl+Y redoes.
  - **Arming:** 1–7 arm whole → 64th notes, R toggles note/rest, `.` toggles the dot, `t` arms the tie tool.
  - **Mode:** Ins toggles Insert/Overwrite.
- **Ties:** with the Tie tool armed, press on one note and release on another
  of the same pitch, earlier or later. A line follows the pointer while
  dragging, and releasing elsewhere cancels. The rule is `Editing.tie`'s:
  same staff, same pitch, touching.
- **Selection menu** (right-click on a selected note or rest, added
  2026-10-22): Delete (closes the gap), Transpose (a step, a semitone or an
  octave, each up or down, or "By interval…" with m2 … P8 up or down),
  Reverse, Copy, Cut.
- **Transpose keys:** Shift+↑/↓ moves the selection an octave; Ctrl+↑/↓ a
  semitone.
- **Context menu** (right-click on an unselected note or rest, nothing armed):
  - Split;
  - Change length (whole → 64th, dot);
  - Make rest / Make note (on the clicked line or space);
  - Tie to next / Untie;
  - Delete.
  - In Insert mode, a longer length first makes room with `insert_time`.
- **Measures:**
  - Hovering a bar shows ⊕ (insert a bar before it) and ⊖ (delete it,
    confirmed if it has notes) at its top-left.
  - An **Add bar** button follows the last bar.
  - The last bar cannot be deleted.

## Saving and settings
- **Save ▾** on the toolbar's right, with a ● marker when `dirty?`:
  - **Save** overwrites this version (`Library.save_version`). On the draft
    it behaves as "Save as new composition".
  - **Save as new version** stores the next version in this key
    (`save_new_version`) and navigates to it. Hidden on the draft.
  - **Save as new composition** opens a dialog for the name (credits
    optional). The name is checked against `get_composition_by_name`, with
    "already taken" shown inline. It creates the composition with v1 and
    navigates there.
- **Settings ⚙ panel:** key, time signature and symbol, tempo and marking,
  pickup.
  - **Key change:** asks to transpose (nearest / up / down) with
    `Transpose.to_key`. On a saved version, the result is saved as a new
    version under the target key with `save_in_key`. On the draft it is
    applied in place.
  - **Time signature or pickup change:** the notes keep their absolute
    positions and re-flow into the new bars (`Timeline.rebar`). Undoable.
  - **Tempo:** stored only; it is used in Phase 5.
- **Unsaved-changes guard:** leaving while `dirty?` asks for confirmation.
  - In-app navigation: the header links and the version picker go through
    a confirm.
  - Closing or reloading the tab: `beforeunload`, set by the hook from the
    dirty flag.
- **Undo across saves:** the undo history survives a Save; saving only
  clears `dirty?`.

## Components
- **`PaletteComponents`:**
  - `palette` (the toolbar);
  - `value_button` (note or rest glyph, with the shortcut in its tooltip and a lock badge when locked);
  - `dot_button`, `accidental_buttons`, `tie_button`, `chord_menu`, `insert_toggle`;
  - `undo_redo`, `save_menu`, `settings_panel`.
- **`EditorComponents`:**
  - `context_menu` (positioned at the pointer);
  - `save_as_dialog`, `transpose_dialog`;
  - `measure_controls` (⊕/⊖).
- **Score:** `ScoreComponents` gains a selection class on events whose ids
  are selected. Notes and rests already have `note-<id>`/`rest-<id>` DOM
  ids.

## Hook: `assets/js/score_editor.js`
- **Geometry:** pure helpers, kept separate and small:
  - `locate(geometry, x, y)` → `{system, measure, tick, staff, step}`;
  - `snap(tick, grid)`;
  - `pitchOf(step, alter, sf)` → MIDI number.
- **Drawing:** an overlay `<svg>` above the score for the cursor glyph, the
  rubber band, the tie line and the pick-up preview. It is
  `phx-update="ignore"`; the server never patches it.
- **Cursor image:** drawn on a canvas with the loaded Bravura font and
  applied with `cursor: url(...)`.
- **Tones:** a `Tone.Synth` with a short envelope.

## Testing (functionality only)
- **Domain:** `insert_time` (shifts one staff only, splits a note sounding
  across the point, appends bars), `split` (notes tied, rests not, 64th
  refused), `set_value` (fits / `:measure_full` / `:overlap`),
  `to_rest`/`to_note` (ties removed).
- **`EditorLive`**, via `render_hook`/`render_click`:
  - place (and an error keeps the item armed);
  - Insert mode;
  - one-shot vs locked arming, and disarm;
  - select, `select_range`, move, delete;
  - pick-up drop;
  - tie (valid and invalid);
  - each context-menu action;
  - copy/paste;
  - undo/redo;
  - add/insert/delete measure;
  - Save, Save as new version, Save as new composition (including the name collision);
  - key change with transpose (draft and saved), time signature re-flow;
  - the dirty marker.
- **Not unit-tested:** the hook's pointer mapping and audio. They are
  checked by hand in a browser (below).

## Verification
- `mix precommit` is clean.
- Manual, in a browser:
  - **Placing:**
    - arm an eighth: the cursor becomes the note, tones play while moving, a click places it, and the pointer returns;
    - double-click to lock, then place several;
    - Esc and right-click cancel;
    - Shift/Ctrl accidentals.
  - **Insert mode:** insert into the middle of a bar; the later notes on
    that staff move right, and the other staff doesn't.
  - **Editing:**
    - pick up a note, drag it, drop it; Esc returns it;
    - rubber band, then arrows, delete, copy/paste;
    - tie by dragging;
    - the context menu's split / length / rest↔note;
    - ⊕/⊖ bars;
    - undo/redo through all of it.
  - **Saving:**
    - Save the draft as a new composition (try a taken name);
    - Save, then Save as new version;
    - change the key (transposed into a new version);
    - change the time signature.
  - **Layouts and themes:** the same placing works in Strip and Page
    layouts and in light and dark themes.
- jj: Phase 4 is its own described change on top of Phase 3.
