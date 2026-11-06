# Components own their events (and their JS)

## Context
`EditorLive` is 1,424 lines with 85 `handle_event` clauses. Most of them aren't
about the editor as a whole. They are the private workings of one component:
`validate_tempo`, `close_save_as`, `arm_chord`, `menu_cut`, `toggle_loop` and so on.
So every component is wired to one LiveView and can't be reused. The 1,034-line
`assets/js/score_editor/index.js` has the same problem on the browser side: one
external hook does the score's pointer work, the keyboard for every control, and
playback.

**The rule from now on:** if a component's events need handlers that exist only to
serve that component, it is a **LiveComponent** with `phx-target={@myself}`. It owns
its events and its private state (forms, open menus, last click), and tells the
parent only about **overall results**: "edit the score with this function", "these
notes are selected", "a version was saved". A component's browser code lives in its
own `render/1` as a **colocated hook** (`<script :type={Phoenix.LiveView.ColocatedHook}
name=".X">`), not in one big JS file. Libraries with no component behaviour (audio
engine, geometry maths, glyph drawing) stay as plain ES modules that the hooks import.

Out of scope: function components that have no events, or whose one event is
already an overall intent. That covers `score/1`, `version_picker` (links only),
`help_components`, `details_button` (an "open details" trigger),
`composition_row`'s delete (an overall action), and generated code
(`core_components.ex`, `layouts.ex`, `user_live/*` forms).

## What makes a component stand alone
Every LiveComponent must work on its own, not only inside `EditorLive`:
- **Declared inputs:** `update/2` reads only the assigns its moduledoc lists. A
  missing required one raises a clear error. It never reaches into the parent's
  assigns, and never assumes another component exists.
- **Declared outputs:** the messages it sends are listed in its moduledoc and
  typespec. They describe results ("these ids are selected", "edit with this
  function"), never "call this handler of EditorLive".
- **Its own JS:** if it has browser code, the colocated hook is in its `render/1`.
  The hook talks only to its own component (`pushEventTo(this.el, …)`) and finds DOM
  only inside `this.el`. A hook that needs another component's data, such as the
  canvas geometry for the playhead, reads it from a documented `data-*` attribute
  passed in as an attr, not from a hard-coded selector.
- **Built from parts:** its markup is composed of function components, each with
  one job. Those can be reused without the LiveComponent.
- **Proven alone:** a small test-only host LiveView
  (`test/support/component_host_live.ex`) mounts any one component with given
  attrs and records the messages it sends. Every component gets a test there, apart
  from the editor.
- **Not brittle:** nothing depends on render order, sibling ids or global JS state,
  apart from the one shared audio engine, which is an explicit imported library.

## How the pieces talk
- **Shared state stays in `EditorLive`:** the `Session` (score, selection,
  clipboard, history), the composition and version, the palette state, the
  instruments, the engraved layout, and which dialog is open.
- **Components get state as attrs** and report through one documented protocol.
  `DrawMusicWeb.Editor.Intent.notify(intent)` does `send(self(), {:editor, intent})`.
  `EditorLive` has one `handle_info` per intent:

  | Intent | Meaning |
  |---|---|
  | `{:edit, fun}` / `{:edit, fun, :select}` | run an edit through `Session.edit` (undo, relayout, stop playback); optionally select the ids it returns |
  | `{:session, fun}` | selection or clipboard change, with no history (drops a paused span) |
  | `{:palette, %EditorPalette{}}` | new palette state (armed, row kind, Insert) |
  | `{:open, dialog}` / `:close` | the single `@dialog` assign |
  | `{:history, :undo \| :redo}` · `{:mode, m}` | — |
  | `{:settings, result}` · `{:transpose, key, dir}` | apply score settings / a new key |
  | `{:saved, version, message}` · `{:composition, c}` | after a save, or after the details change |
  | `{:instrument, :playback \| :version, program}` | — |
  | `{:flash, kind, msg}` | a component's flash only reaches the layout through the parent |

  That's about 14 clauses in place of 85.
- **Reusable components** (used outside the editor) follow the phx.gen.live
  convention instead: `send(self(), {__MODULE__, result})`.
- **Mode gating moves into the components:** each one gets `editor_mode` and ignores
  events that don't fit it. The global `@edit_events`/`@play_events` lists go away.
- **Commands from the parent to a component** go through `send_update`, for example
  `Transport.stop/0` after an edit, or `Transport.selection_changed/0`.
- **The one open dialog** is a single `@dialog` assign (`nil | {:tempo, target} |
  {:menu, %ContextMenu{}} | :settings | {:transpose, key} | :save_as | :details`),
  rendered by one `<.editor_dialog dialog={@dialog} … />`.

## The components
New editor LiveComponents go in `lib/draw_music_web/live/editor/` as
`DrawMusicWeb.Editor.*`. Shared ones go in `lib/draw_music_web/components/live/`.

| LiveComponent | Absorbs (events now in a LiveView) | Reports |
|---|---|---|
| `DetailsDialog` (shared: editor + library) | edit/validate/save/close_details, `store_details` (draft vs saved via attr) | `{:saved, composition}`, `:closed` |
| `LayoutToggle`, `InkPicker` (shared: editor + user settings) | `set_score_layout`, `set_score_ink`; `ScorePreferences.apply_event` goes | `{:updated, user}` |
| `Library.ImportDialog` | the 7 import events and the upload (`allow_upload` in the component) | `{:imported, composition}`, `:closed` |
| `Editor.SaveMenu` + `Editor.SaveAsDialog` | save, save_new_version, open/validate/close save_as, save_as | `{:saved, …}`, `{:open, :save_as}` |
| `Editor.SettingsDialog` + `Editor.TransposeDialog` | open/apply/close settings, transpose_key, cancel_transpose | `{:settings, …}`, `{:transpose, …}` |
| `Editor.TempoDialog` | validate/save/delete/close_tempo (the `TempoDialog` struct becomes `TempoTarget{id, tick, params}`; the form lives in the component) | `{:edit, …, :select}`, `:close` |
| `Editor.NoteMenu` (context menu) | close_menu, menu_copy/cut/tempo, the 11 `@menu_events` | `{:edit, …}`, `{:session, …}`, `{:open, {:tempo, …}}` |
| `Editor.Palette` | toggle_mode, arm*, single_notes, toggle_rest/dot/insert, set_accidental, select_all, undo/redo, open_settings, open_help; colocated `.PaletteKeys` hook (its keyboard shortcuts) | `{:palette, …}`, `{:edit, …}`, `{:mode, …}`, `{:history, …}`, `{:open, …}` |
| `Editor.Transport` (inside the palette in Play) | play, rewind, skip, stop, toggle_loop, playback_state/ended, set/use_playback_instrument; **owns playback state and loop**; colocated `.Transport` hook (audio, playhead, play keys) | `{:session, …}` (skip/start point), `{:instrument, …}`, `{:flash, …}` |
| `Editor.ScoreCanvas` (the hook div, score, overlay, measure controls) | place, select*, preview_range (`{:reply, …}`), clear_selection, set_last_click (now private to the component), drop, tie, move/resize/edit_tempo, open_menu, audition, disarm, the measure events, move/delete/copy/cut/paste; colocated `.ScoreCanvas` hook (pointer, drag, previews, edit keys) | `{:edit, …}`, `{:session, …}`, `{:open, …}`, `{:palette, …}` |

**Help** has only open and close, so it needs no server at all. It becomes
`JS.show`/`JS.hide` on an always-rendered dialog, and the `?` key runs the same
command with `this.js()`.

### JS split
`score_editor/index.js` breaks up by owner:
- **`.ScoreCanvas` hook:** pointer, drag, placement, selection band, context menu
  and the edit keys.
- **`.Transport` hook:** the `play`/`pause`/`resume`/`rewind`/`skip`/`loop`/`stop`/
  `audition` handleEvents, the playhead, and the play keys.
- **`.PaletteKeys` hook:** the palette shortcuts.

Each hook uses `this.pushEventTo(this.el, …)`. Shared code stays as imported
libraries: `audio.js` (one shared instance, so drag tones and playback use the same
engine), `geometry.js`, `chord.js`, `cursor.js`, `playhead.js`, `keys.json`, and a
new small `keyboard.js` (the `typing()`/dialog-open/`keyId` helpers). To import them
by name from colocated hooks, add `assets/js` to esbuild's `NODE_PATH` in
`config/config.exs`. **PR 9 checks this first**; if it doesn't resolve, use a
relative import from the colocated output. Each colocated hook stays short (glue
only), so no module goes over ~500 lines. When the last hook moves out, the external
`ScoreEditor` hook is removed from `app.js`.

## PRs (in order; each small, `mix precommit` clean, reviewed and merged before the next)
1. **Pure logic out of `EditorLive`**, no behaviour change:
   - `play_span`/`skip_*` → `Music.Playback`;
   - `menu_for`/`menu_target` → `ContextMenu`;
   - `copy`/`paste_at` → `EditorCommands`;
   - `version_attrs`/`draft_name`/`changeset_message` → `EditorSaving`.
2. **`Editor.Intent` + the single `@dialog` assign + the test-only
   `ComponentHostLive`:** `EditorLive`'s `handle_info` intents (still fed by the
   old handlers for now).
3. **`DetailsDialog`**, shared by `EditorLive` and `LibraryLive`.
4. **`LayoutToggle` + `InkPicker`**, shared by `EditorLive` and `UserLive.Settings`.
5. **`Library.ImportDialog`.**
6. **`Editor.SaveMenu` + `SaveAsDialog`.**
7. **`Editor.SettingsDialog` + `TransposeDialog`**, and help moves to JS commands.
8. **`Editor.TempoDialog` + `Editor.NoteMenu`.**
9. **Palette, in two parts:**
   - **9a:** split into function sub-components, a refactor only, per
     `plans/palette-component-review.md`;
   - **9b:** `Editor.Palette` LiveComponent + the `.PaletteKeys` colocated hook
     (also the `NODE_PATH` import check).
10. **`Editor.Transport`** + `.Transport` hook; the audio code moves out of `index.js`.
11. **`Editor.ScoreCanvas`** + `.ScoreCanvas` hook; `index.js` and the external hook
    are deleted.
12. **Compose `EditorLive.render/1`** (`editor_header`, `editor_dialog`) and group the
    leftover assigns into structs.

13. **Final cleanup: function order.** Reorder every non-generated module in
    `lib/` into the three groups (public, `@impl`, private), each in
    alphabetical order. A mechanical sweep, split by area into its own PRs.
    Until then, new and changed code already follows the rule.

**Expected result:** `EditorLive` keeps mount, render (~50 lines of contents),
`apply_edit`/layout helpers and the intent `handle_info`s, at about 350 lines with
no component-specific `handle_event`. `LibraryLive` drops its import and details
handlers.

## Conventions kept
- Element ids and the user-visible behaviour stay the same.
- Public functions come first and private last. Every public function gets an
  `@spec`, including LiveComponent callbacks marked `@impl`.
- Fixed-shape data gets structs (`EditorPalette`, `TempoTarget`).
- Templates live in `render/1`.
- Each component reads like a table of contents of named sub-components.

## Verification
- **Tests:** the `element(...) |> render_click()` tests follow `phx-target` without
  changes. The ~110 `render_hook(view, "…")` calls become
  `view |> element("#score-editor" | "#palette" | "#transport") |> render_hook(…)`.
  New tests cover each component's own behaviour (dialog validate/save/close, the
  palette arming, transport states) and the parent's intents. Per
  [[tests-functionality-only]], there are no Ecto round-trips.
- Run `mix precommit` at every PR.
- After each of PRs 7–11, you check the editor in the browser in both modes
  (placing, dragging, the context menu, the tempo dialog, playback, the keys). You
  run the dev server.
- `/help`: there are no new keys or mouse actions, so no cheat-sheet changes are
  expected; if a PR changes one, it updates the cheat sheet in the same PR.
