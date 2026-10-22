# Phase 4 Editing: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the score editable: a palette, placing notes, rests and
chords with a glyph cursor and hover tones, selection, moving, pick-up,
ties, a context menu, measures, undo/redo, saving and score settings.

**Architecture:**
- The server owns the score. A pure `DrawMusic.Music.Session` holds the
  score, context, selection, clipboard and undo history; `EditorLive`
  wraps it with the palette state (armed item, Insert mode) and turns
  events into `Editing` calls.
- A `ScoreEditor` JS hook maps the pointer to musical positions from
  geometry JSON, draws the cursor and previews, plays tones, and sends
  semantic events.

**Tech Stack:** Elixir/Phoenix LiveView 1.2, function components, Tailwind
v4, Bravura (SMuFL), Tone.js (npm), jj (colocated).

**Spec:** `plans/phase-4-editing.md`

## Global Constraints
- **Sources of truth:** the domain is `DrawMusic.Music.*`; nothing music-logical is reimplemented in JS.
- **UI:** built from function components (`PaletteComponents`, `EditorComponents`); no LiveComponents.
- **Event params from the hook are untrusted:**
  - note values come from `Duration.values()` and are matched by string, never `String.to_atom`;
  - staff is `"treble" | "bass"`; alter is `-2..2`; ids are checked against the score.
- **Tests:** functionality only. No Ecto round-trip or default tests; LiveView tests use element ids.
- **Edits:** only in manual permission mode (the user's hook). No file changes via Bash while in auto mode.
- **jj:** all work goes in change `zvxrxxzt` ("Editing (Phase 4…)"). Run `mix test` green at each task's end, and `mix precommit` at the end.
- **Copy:** error messages per reason:
  - `:measure_full` → "That bar is full"
  - `:overlap` → "Something is already there"
  - `:duplicate` → "That note is already there"
  - `:out_of_range` → "That would go outside the piano's range"
  - `:not_tieable` → "Only touching notes of the same pitch can be tied"
  - `:last_measure` → "A score needs at least one bar"
  - `:unrepresentable` → "That length can't be written as one note"
  - `:no_such_measure` → "That bar no longer exists"
  - `:before_start` → "That would move before the start"
  - `:not_found` → "That note no longer exists"

## Review Focus
1. **A double-click on a palette item also sends two single clicks.**
   Arming the same item twice must keep it armed, and the lock must end
   armed and locked. (Task 4 test)
2. **A click made with stale geometry** (a measure index past the end, or
   an offset past capacity) must give a message, not a crash. (Task 5 test)
3. **Forged hook params** (an unknown value or staff, a non-integer step,
   alter 9) are ignored with an error message. (Task 5 test)
4. **Undo after Save** marks the score dirty again; redo back to the saved
   state still shows dirty. That's simple and safe. (Task 3 test)
5. **A selection holding ids that undo or delete removed** is pruned, and a
   move with stale ids doesn't crash. (Task 3 and Task 7 tests)

---

### Task 1: `Editing.insert_time/5`

**Files:**
- Modify: `lib/draw_music/music/editing.ex`
- Test: `test/draw_music/music/editing_test.exs` (new `describe "insert_time"`)

**Interfaces:**
- Produces: `Editing.insert_time(score, ctx, at :: non_neg_integer, ticks :: pos_integer, staff :: :treble | :bass) :: {:ok, score} | {:error, reason}`

- [ ] **Step 1: Write the failing tests**
  - `"shifts later events on that staff only"`:
    - set up a treble quarter at 0 and at 960, and a bass whole at 0;
    - `insert_time(s, ctx, 960, 480, :treble)`;
    - expect `notes(s)` = treble C4 at 0, treble at 1440, bass whole at 0 unchanged.
  - `"splits a note sounding across the point and drops its tie"`:
    - a treble half at 0, `insert_time(.., 960, 960, :treble)`;
    - expect two quarters at 0 and 1920, and `tie_chain(s, id) == [id]`.
  - `"appends bars when pushed past the end"`:
    - in `Score.new(1)`, a whole at 0, `insert_time(.., 0, 960, :treble)`;
    - expect `length(s.measures) == 2` and the note tied across the bar.
- [ ] **Step 2: Run** `mix test test/draw_music/music/editing_test.exs`. It fails (undefined function).
- [ ] **Step 3: Implement.** Flatten with `Timeline.flatten/2` and split the
  staff's entries that satisfy `start < at < start + ticks` into a head
  (`at - start`) and a tail starting at `at`, with the tail getting a fresh
  id. Add `ticks` to the start of every entry on `staff` with start ≥ `at`.
  Then the private `rebuild/3` (the existing path through `check_layout` →
  `rebar` → `prune_ties` drops the broken tie).
- [ ] **Step 4: Run** the tests; they pass. Then the full `mix test` passes.

### Task 2: `split`, `set_value`, `to_rest`, `to_note`, `rebar_to`

**Files:**
- Modify: `lib/draw_music/music/editing.ex`
- Test: `test/draw_music/music/editing_test.exs`

**Interfaces:**
- Produces:
  - `split(score, ctx, id) :: {:ok, score, [id1, id2]} | {:error, :unrepresentable | :not_found}`
  - `set_value(score, ctx, id, value, dots) :: {:ok, score} | {:error, reason}`
  - `to_rest(score, ctx, id) :: {:ok, score, rest_id}`
  - `to_note(score, ctx, id, step, alter) :: {:ok, score, note_id}`
  - `rebar_to(score, from_ctx, to_ctx) :: {:ok, score} | {:error, reason}`: keeps every event's absolute start and re-flows it into `to_ctx`'s bars, starting from one empty measure.

- [ ] **Step 1: Write the failing tests:**
  - `split`:
    - a quarter note becomes two tied eighths (`tie_chain` length 2);
    - a dotted quarter becomes quarter + eighth;
    - a quarter rest becomes two eighth rests with no tie;
    - a 64th gives `{:error, :unrepresentable}`.
  - `set_value`:
    - a quarter to a half when there is room → ok;
    - a quarter at offset 2880 to a half → `{:error, :measure_full}`;
    - into a following note in the same voice → `{:error, :overlap}`.
  - `to_rest`: a tied note becomes a rest, and the tie into it is removed (`tie_chain(s, a) == [a]`).
  - `to_note`: the rest becomes a note at the given step, keeping its length.
  - `rebar_to`: from 4/4 to 3/4, a half note at tick 2880 becomes a quarter at the end of bar 0 tied to a quarter at the start of bar 1.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement**, all through `Timeline.flatten` → modified entries → `rebuild`.
  - For `split`:
    - an undotted value splits into two of the next shorter value;
    - a dotted value splits into the same value with one dot fewer, plus
      the remainder (dotted quarter → quarter + eighth; double-dotted
      half → dotted half + eighth);
    - a 64th is `:unrepresentable`.
  - `to_note` and `to_rest` reuse the event's offset, value and dots.
- [ ] **Step 4: Run.** It passes; full `mix test` passes.

### Task 3: `DrawMusic.Music.Session`

**Files:**
- Create: `lib/draw_music/music/session.ex`
- Test: `test/draw_music/music/session_test.exs`

**Interfaces:**
- Produces:
  - `%Session{score, ctx, selection: MapSet, clipboard: nil | map, undo: [{score, ctx}], redo: [{score, ctx}], dirty?: false}`
  - `new(score, ctx) :: Session`
  - `edit(session, (score, ctx -> {:ok, score} | {:ok, score, extra} | {:error, r})) :: {:ok, session, extra | nil} | {:error, r}`: pushes `{score, ctx}` onto `undo`, clears `redo`, sets `dirty?`, and prunes the selection to ids still present.
  - `change_context(session, ctx, score) :: session`: the same bookkeeping, for settings changes.
  - `undo(session)` and `redo(session) :: session`: no-ops when the stack is empty; both set `dirty?: true` and prune the selection.
  - `saved(session) :: session`: `dirty?: false`.
  - `select(session, ids, add? :: boolean)`, `toggle(session, id)`, `clear_selection(session)`; ids not in the score are ignored.
  - `event_ids(session) :: MapSet`

- [ ] **Step 1: Write the failing tests:**
  - an edit then undo restores the score; redo re-applies it;
  - a new edit clears redo;
  - an error leaves the session unchanged;
  - `saved` clears `dirty?`, and **undo after saved sets `dirty?` again** (Review Focus 4);
  - **after undo removes a selected note, `selection` no longer holds its id** (Review Focus 5);
  - `select` ignores unknown ids.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement** as a plain struct module, no processes.
- [ ] **Step 4: Run.** It passes.

### Task 4: Palette and armed state

**Files:**
- Create: `lib/draw_music_web/components/palette_components.ex`
- Modify: `lib/draw_music_web/live/editor_live.ex` (mount builds a `Session`; assigns `armed`, `insert?`)
- Test: `test/draw_music_web/live/editor_palette_test.exs`

**Interfaces:**
- Consumes: `Session.new/2`, plus `Duration.values/0` and `Chords.qualities/0`.
- Produces:
  - **Assigns:**
    - `@session`;
    - `@armed` (`nil | %{kind: :note | :rest | :chord | :tie, value: atom, dots: 0..2, alter: nil | -2..2, chord: nil | {:quality, atom} | {:degree, 1..7}, locked?: boolean}`);
    - `@insert?`.
  - **DOM ids:**
    - `palette`;
    - `palette-<value>` (e.g. `palette-eighth`), `palette-rest-toggle`, `palette-dot`, `palette-sharp`, `palette-flat`, `palette-natural`;
    - `palette-tie`, `palette-chords`, `palette-chord-<quality>`, `palette-degree-<n>`;
    - `palette-insert`, `palette-undo`, `palette-redo`.
  - **Events:**
    - `arm` `%{"kind", "value"}`, `lock` `%{"kind", "value"}`;
    - `disarm`, `toggle_rest`, `toggle_dot`, `set_accidental` `%{"alter"}`;
    - `toggle_insert`, `arm_chord` `%{"quality" | "degree"}`, `arm_tie`.
  - **Engraving:** `ScoreComponents.systems/1` gains a `selection` attr (MapSet). Selected glyphs get `class="selected"`, and `app.css` defines `--score-selection` per theme.

- [ ] **Step 1: Write the failing tests:**
  - clicking `#palette-eighth` sets `armed` to an eighth note (assert `#palette-eighth[aria-pressed=true]`);
  - `disarm` clears it;
  - **arming the same item twice keeps it armed; `lock` leaves it armed and locked**, with `#palette-eighth [data-locked]` present (Review Focus 1);
  - `toggle_dot` with nothing armed and a selection sets the selected notes' dots (via `set_dots`); with an item armed it modifies `armed.dots`.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement** the components.
  - Value buttons show Bravura glyphs (the `text` uses `Smufl.char/1`, with `font-family: Bravura`) and the shortcut in the `title`.
  - `phx-click="arm"` and `phx-dblclick="lock"`.
  - Use `<.icon>` for undo/redo.
  - The palette is `sticky top-0 z-10`, on the score paper color.
- [ ] **Step 4: Run.** It passes.

### Task 5: Placing (server) and geometry for the hook

**Files:**
- Create: `lib/draw_music_web/editor_geometry.ex`
- Modify: `lib/draw_music_web/live/editor_live.ex`
- Test: `test/draw_music_web/live/editor_place_test.exs`

**Interfaces:**
- Consumes: `Session.edit/2`, `Editing.place_note/4`, `place_rest/4`, `place_chord/5`, `insert_time/5` (Task 1), and `Chords.build/3`, `diatonic/4`.
- Produces:
  - `EditorGeometry.encode(engraved, ctx) :: map`, JSON for the hook:
    - `%{systems: [%{y, measures: [%{index, x, width, start_tick, capacity, content_x, scale}]}]}`;
    - `staff_top: %{treble: 0, bass: 12}` and `top_step: %{treble: 38, bass: 26}`;
    - `sf`, `beat_ticks`, and `space` (px per staff space, 10).
  - **Hook element:** `<div id="score-editor" phx-hook="ScoreEditor" data-geometry={JSON} data-armed={JSON}>` wraps the score. On every change the LiveView pushes `push_event("geometry", ...)` and `push_event("armed", ...)`.
  - **Event:** `place` `%{"measure", "offset", "staff", "step", "alter"}` (alter omitted means the key's alter).
  - **Helper:** `EditorLive.error_message(reason) :: String.t()`, with the copy from Global Constraints.

- [ ] **Step 1: Write the failing tests**, using `render_hook(view, "place", %{...})`:
  - an armed eighth placed at measure 0, offset 480, treble, step 32 → `#score [id^='note-']` count 1, and `armed` is nil afterwards (one-shot);
  - with `lock`, two places leave the item armed;
  - **placing into a full bar flashes "That bar is full" and keeps the item armed**;
  - **`place` with measure 99 flashes "That bar no longer exists"** (Review Focus 2);
  - **`place` with `"value" => "bogus"`, `"staff" => "alto"` or `"alter" => 9` gives an error and no crash** (Review Focus 3);
  - Insert mode: a quarter placed at offset 0 in a bar holding a quarter at 0 → the old note is now at offset 960, and the bass staff is untouched;
  - an armed chord quality `major` placed at C4 → three notes C4, E4, G4;
  - degree 5 in G major → D, F♯, A;
  - an armed rest → a rest with the `rest-` DOM id.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement** `handle_event("place", ...)`.
  - Parse with a whitelist; Insert mode calls `insert_time(score, ctx, start, ticks, staff)` first, in one `Session.edit` via a `with` inside the fun.
  - On ok: disarm unless `locked?`, re-engrave, push geometry.
  - On error: `put_flash(:error, error_message(reason))`.
- [ ] **Step 4: Run.** It passes.

### Task 6: `ScoreEditor` hook: cursor, tones, placing, cancel

**Files:**
- Create: `assets/js/score_editor/geometry.js` (pure: `locate`, `snap`, `pitchOf`), `assets/js/score_editor/cursor.js` (glyph-to-canvas CSS cursor), `assets/js/score_editor/index.js` (the hook)
- Modify: `assets/js/app.js` (register `ScoreEditor`), `mix.exs` (`assets.setup` runs `cmd --cd assets npm install`), `assets/package.json` (via `npm i tone --prefix assets`)

**Interfaces:**
- Consumes: `data-geometry`, `data-armed`, and the `geometry` / `armed` events (Task 5).
- Produces:
  - `locate(geometry, x, y) -> {system, measure, tick, staff, step} | null`, where y is in staff spaces relative to the system and the closer staff wins in the gap;
  - `snap(offset, gridTicks) -> offset`, with the grid being the undotted value's ticks;
  - `pitchOf(step, alter, sf) -> midi`;
  - the overlay `<svg id="score-overlay" phx-update="ignore">`.

- [ ] **Step 1:** Run `npm i tone --prefix assets`; `assets/package.json` lists `tone`.
- [ ] **Step 2: Implement the hook:**
  - On `mousemove` over the score: `locate`, then `snap`. Draw the armed glyph at the snapped spot in the overlay, and hide the system cursor (`cursor: none`) while armed.
  - Play a `Tone.Synth` note of 0.12 s each time `(staff, step, alter)` changes. Start `Tone.start()` on the first pointerdown.
  - Shift → +1, Ctrl/Alt → −1 shows ♯/♭ beside the glyph.
  - Click → `pushEvent("place", ...)`.
  - **Esc** or **contextmenu** while armed → `pushEvent("disarm")`, with `preventDefault` on `contextmenu`.
  - Outside the score while armed, `document.body.style.cursor = cursorFor(glyph)` (from cursor.js), reset on disarm.
- [ ] **Step 3: Manual check** (`mix phx.server`):
  - arm an eighth: the cursor becomes the note, and tones play per line or space;
  - a click places it and the pointer returns;
  - double-click locks it;
  - Esc and right-click cancel.
  - Same checks in the Page layout.
- [ ] **Step 4:** `mix test` still passes, and `mix assets.build` succeeds.

### Task 7: Selection, keyboard, clipboard, undo/redo

**Files:**
- Modify: `lib/draw_music_web/live/editor_live.ex`, `assets/js/score_editor/index.js`
- Test: `test/draw_music_web/live/editor_select_test.exs`

**Interfaces:**
- Consumes: `Session.select/3`, `toggle/2`, `edit/2`, `undo/1`, `redo/1`, and `Editing.select_range/5`, `move_steps/4`, `shift/4`, `remove/3`, `copy/3`, `paste/4`, `insert_time/5`.
- Produces:
  - **Events:**
    - selecting: `select` `%{"ids", "add"}`, `select_range` `%{"from", "to"}`, `clear_selection`;
    - moving: `move` `%{"dir" => "up" | "down" | "left" | "right"}`;
    - editing: `delete`, `copy`, `cut`, `paste` `%{"at" => tick | nil}`, `set_last_click` `%{"at"}`;
    - history: `undo`, `redo`.
  - **Hook:**
    - Shift-click toggles; dragging on empty staff draws the rubber band (overlay rect) → `select_range`;
    - left-click on a rest → `select` alone;
    - keys per the spec (arrows, Delete/Backspace, Ctrl+C/X/V/Z/Y, Ctrl+Shift+Z, 1–7, R, `.`, t, Ins, Esc).
    - Keys are ignored while focus is in an input.

- [ ] **Step 1: Write the failing tests:**
  - `select_range` over bar 0 selects all its events (assert `.selected` count);
  - `move` up turns E4 into F4;
  - `move` right shifts by one beat;
  - `delete` removes;
  - copy then `paste` at 3840 duplicates into bar 1;
  - in Insert mode, paste shifts that staff's later events;
  - undo/redo round-trip via `#palette-undo`/`#palette-redo`;
  - **`move` after the selected note was deleted by undo → no crash, nothing selected** (Review Focus 5);
  - moving out of range → "That would go outside the piano's range", and the score is unchanged.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement** the server handlers, then the hook parts.
- [ ] **Step 4: Run** the tests; they pass. Manually check the rubber band and keys.

### Task 8: Pick-up, ties, context menu, measures

**Files:**
- Create: `lib/draw_music_web/components/editor_components.ex` (`context_menu`, `measure_controls`)
- Modify: `lib/draw_music_web/live/editor_live.ex`, `assets/js/score_editor/index.js`
- Test: `test/draw_music_web/live/editor_tools_test.exs`

**Interfaces:**
- Consumes: `Editing.move_steps/4`, `set_alter/4`, `tie/4`, `untie/2`, `split/3`, `set_value/5`, `to_rest/3`, `to_note/5`, `insert_measure/2`, `append_measure/1`, `delete_measure/3`.
- Produces:
  - **Events:**
    - pick-up and ties: `drop` `%{"ids", "steps", "alter"}`, `tie` `%{"from", "to"}`;
    - context menu: `open_menu` `%{"id", "x", "y", "step"}`, `close_menu`;
    - menu actions: `split`, `set_value` `%{"value", "dots"}`, `to_rest`, `to_note`, `untie` (on `@menu.id`);
    - measures: `insert_measure` / `delete_measure` `%{"index"}`, `add_measure`.
  - **Assigns:** `@menu` (`nil | %{id, x, y, step, staff}`).
  - **DOM ids:** `context-menu`, `menu-split`, `menu-length-<value>`, `menu-to-rest`, `menu-to-note`, `menu-untie`, `menu-delete`, `measure-<i>-insert`, `measure-<i>-delete`, `add-measure`.

- [ ] **Step 1: Write the failing tests:**
  - `drop` with steps 2 moves C4 to E4; with alter 1, to E♯4;
  - `tie` on two touching C4s ties them; on C4/D4 it flashes the not-tieable copy;
  - the menu's split, length, to-rest and to-note each do their `Editing` call;
  - in Insert mode, lengthening via the menu shifts later notes on that staff;
  - `measure-0-insert` adds a bar before 0;
  - deleting the only bar flashes "A score needs at least one bar";
  - `add-measure` appends.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement** the server and components, then the hook.
  - **Pick-up:** a left-click on a note with nothing armed lifts it (plus the selection if the note is selected). An overlay preview follows by steps with tones; a second click sends `drop`; Esc or right-click restores.
  - **Tie tool:** a drag line from pointerdown to pointerup over another note → `tie`.
  - **Context menu:** `contextmenu` on a note or rest with nothing armed → `open_menu`.
  - **Measure controls:** ⊕/⊖ shown on hover. Delete asks for confirmation (`data-confirm`) when the bar has notes.
- [ ] **Step 4: Run** the tests; they pass. Manually check the pick-up, the tie drag and the menu placement near the window edges.

### Task 9: Save menu, save-as dialog, dirty guard

**Files:**
- Modify: `lib/draw_music_web/components/palette_components.ex` (`save_menu`), `lib/draw_music_web/components/editor_components.ex` (`save_as_dialog`), `lib/draw_music_web/live/editor_live.ex`, `assets/js/score_editor/index.js`
- Test: `test/draw_music_web/live/editor_save_test.exs`

**Interfaces:**
- Consumes: `Library.save_version/3`, `save_new_version/3`, `create_composition/4`, `Session.saved/1`, and `LibraryComponents.version_path/3`.
- Produces:
  - **Events:** `save`, `save_new_version`, `open_save_as`, `validate_save_as` / `save_as` `%{"composition" => %{"name", credits…}}`, `close_save_as`.
  - **Version attrs** from the session: `%{score, time_num, time_den, time_symbol, tempo_bpm, tempo_text, pickup_ticks}`.
  - **DOM ids:** `save-menu`, `save`, `save-new-version`, `save-as`, `save-as-form`, `dirty-marker`.
  - **Dirty guard:** `data-dirty` on `#score-editor`. While it's `"true"`, the hook adds a `beforeunload` listener and a capture-phase click listener on `a[data-phx-link]` that asks `confirm("Leave without saving?")` and stops the navigation if cancelled.

- [ ] **Step 1: Write the failing tests:**
  - after an edit `#dirty-marker` is shown, and `save` hides it and persists (reload: `Library.get_version!` has the note);
  - `save-new-version` navigates to `v/2`;
  - on the draft `/`, `save` opens the save-as form; a new name creates and navigates;
  - **a taken name shows "has already been taken" inline and stays put**;
  - `#save-new-version` is not rendered on the draft.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** It passes. Manually check that the leave-confirm appears for the header links and on reload.

### Task 10: Score settings panel

**Files:**
- Modify: `lib/draw_music_web/components/palette_components.ex` (`settings_panel`), `lib/draw_music_web/components/editor_components.ex` (`transpose_dialog`), `lib/draw_music_web/live/editor_live.ex`
- Test: `test/draw_music_web/live/editor_settings_test.exs`

**Interfaces:**
- Consumes: `Session.change_context/3`, `Editing.rebar_to/3` (Task 2), `Transpose.to_key/4`, `Library.save_in_key/4`, and `Key.slug/2` (`NewCompositionLive`'s key options can be reused).
- Produces:
  - **Events:** `open_settings`, `close_settings`, `apply_settings` `%{"settings" => %{"key", "time_num", "time_den", "time_symbol", "tempo_bpm", "tempo_text", "pickup_beats"}}`, `transpose` `%{"direction"}`, `cancel_transpose`.
  - **DOM ids:** `settings-button`, `settings-form`, `transpose-dialog`, `transpose-nearest` / `-up` / `-down`.

- [ ] **Step 1: Write the failing tests:**
  - changing 4/4 to 3/4 re-flows a half at 2880 into a tie across the bar, and undo restores it;
  - on the draft, a key change to G with "nearest" turns C4 into G3 in place, and the dirty marker shows;
  - on a saved version, a key change saves a new version under `g-major` and navigates there;
  - a pickup longer than the bar is refused with the Version changeset's message;
  - a tempo change is stored on Save.
- [ ] **Step 2: Run.** It fails.
- [ ] **Step 3: Implement.** Validate settings with `Version.changeset/2` on a scratch `%Version{}`, as `NewCompositionLive` does.
- [ ] **Step 4: Run.** It passes.

### Task 11: Finish

- [ ] **Step 1:** Run `mix precommit`. It's clean: no warnings, no Credo issues, all tests passing.
- [ ] **Step 2:** Run the spec's manual verification list in a browser (Strip and Page, light and dark).
- [ ] **Step 3:** `jj describe -m "Editing: palette, placing, selection, ties, context menu, measures, undo, save, settings"` plus the Co-Authored-By trailer. Don't move `master` until the user approves Phases 3 and 4.
