# Review: `lib/draw_music_web/live/editor_live.ex` (from the Phase 5 code review)

Recorded 2026-11-04. These are strategies for Phase 8; nothing is built until the user approves.

## The problem
`EditorLive` is 1,424 lines:
- 85 `handle_event` clauses, 91 `defp`s, and about 25 flat assigns;
- a 153-line `render/1`;
- 17 aliases.

It handles modes, the palette, placing, selection, editing the selection, pick-up and ties, the context menu, tempo changes, measures, saving, composition details, score settings and transposition, playback, history, preferences and layout. Some logic has already moved out (`EditorCommands`, `EditorPlacement`, `EditorSettings`, `EditorPalette`, `EditorGeometry`, `ContextMenu`, `TempoForm`). But every event still enters through one module, and the helper sections ("Playback helpers", "Settings helpers", "Saving helpers") are still here.

## Redundancies
- **Six close handlers:** `close_help`, `close_menu`, `close_tempo`, `close_save_as`, `close_details` and `close_settings`, each backed by its own nil-able assign (`help?`, `menu`, `tempo`, `save_as_form`, `details_form`, `settings_form`, and `pending_key` for the transpose prompt).
  - Only one overlay is ever open at a time, so a single `:dialog` assign (`nil | {:save_as, form} | {:details, form} | {:settings, form} | {:transpose, key} | %TempoDialog{} | :help | %ContextMenu{}`) and one `close_dialog` event would replace them.
  - The dialog markup in `render/1` would collapse to one `<.dialog dialog={@dialog} />`.
- **Mode gating:** one `@edit_events` / `@play_events` guard pair at the top, plus per-clause guards (`%{assigns: %{editor_mode: :play}}`). Once events are grouped by feature, each group knows its mode.
- **Logic that isn't about the LiveView:**
  - `skip_target`, `skip_points`, `play_span` and `span_end` are timeline maths and belong in `Music.Playback`;
  - `version_attrs`, `draft_name` and `in_new_key` belong in `Library` or a small `EditorSaving`;
  - `menu_for` and `menu_target` belong in `ContextMenu`;
  - `copy` and `paste_at` belong in `EditorCommands`.

## Strategies

### A. Nested LiveViews (`live_render`, each a sub-view in its own process)
**Not recommended.**
- Almost everything acts on the one `Session` (the score, selection, undo history and context). Separate processes would each need a copy, kept in step by messages. That means race conditions, duplicate engraving and slower edits.
- The palette, score, transport and dialogs aren't independent views; they're controls over the same state.
- Nested LiveViews suit truly independent panels, such as a library sidebar. Nothing in the editor qualifies.

### B. LiveComponents (sub-views with their own state and handlers, in the same process)
**Recommended for the form dialogs only.** This is the "strong, specific need" the project's guidelines ask for before using them.
- `SaveAsDialog`, `DetailsDialog`, `SettingsDialog` (with its transpose prompt) and `TempoDialog`.
- Each owns its form, its `validate`/`submit`/`close` events and its changeset handling (`phx-target={@myself}`).
- When it's done, it tells the parent through `send(self(), {:dialog_done, result})`. The parent applies anything that changes the session (new settings, a tempo change, a saved version) in one `handle_info` per result.
- This removes about 20 handlers and the form assigns from `EditorLive`. Each dialog becomes one self-contained file a reader can take in whole.

### C. Event-handler modules attached with `attach_hook/4` (same process, shared socket)
**Recommended for everything that edits the session.** `Phoenix.LiveView.attach_hook(socket, name, :handle_event, &Module.handle_event/3)` runs a module's `handle_event/3` before the LiveView's own. The module returns `{:halt, socket}` when it handled the event, or `{:cont, socket}` to pass it on. Feature modules then own their events and helpers without message passing:

| Module (`DrawMusicWeb.EditorLive.*`) | Events | Est. lines |
|---|---|---|
| `Modes` (the first hook: the mode gate, help, the layout preference) | toggle_mode, open_help, set_score_layout, the edit/play gate | ~80 |
| `PaletteEvents` | arm, arm_value, arm_chord, single_notes, arm_tie, disarm, toggle_rest, toggle_dot, set_accidental, toggle_insert | ~110 |
| `SelectionEvents` | select, select_range, preview_range, select_all, clear_selection, set_last_click (the cursor, in Phase 8) | ~90 |
| `EditEvents` | place, move, delete, copy, cut, paste, drop, tie, the measures, undo, redo | ~220 |
| `MenuEvents` | open_menu, menu_*, the `@menu_events` group | ~110 |
| `PlaybackEvents` | play, rewind, skip, stop, toggle_loop, playback_state, playback_ended, audition, the instrument | ~220 |
| `KeyEntry` events (new in Phase 8) | play_keys | ~60 |

Each module's `attach/1` is called from `mount/3`. The shared helpers they all use (`edit/2`, `edit_and_select/3`, `apply_edit`, `lay_out`) go in one `EditorLive.Edit` module.

**The cost:** which module handles an event is no longer visible in `EditorLive` itself. To make up for it:
- `mount/3` lists the hooks in order, with one comment each;
- each module's moduledoc lists its events;
- optionally, event names get a prefix (`"playback:play"`) so the owner is obvious at the call site. That touches the JS `pushEvent` calls, the `phx-click`s and the tests, so it would be a later, separate step.

Plain delegation (`def handle_event("play" = e, p, s), do: PlaybackEvents.handle_event(e, p, s)`) is the alternative without hooks. It's more explicit, but it keeps 85 one-line clauses in `EditorLive`. Hooks are the better fit at this size.

### D. Group the assigns into structs
Replace about 25 flat assigns with a few named structs that the matching modules own (see [[structs-not-naked-maps]]):
- `palette` (`armed`, `row_kind`, `insert?`);
- `playback` (`state`, `loop?`, `instrument`, `instrument_source`, `version_instrument`);
- `dialog` (strategy B or the single `:dialog` above);
- `layout` (`engraved`, `pieces`, `geometry_json`, `score_loading?`).

Change tracking still works, because LiveView tracks the top-level assign and the components take the struct's fields.

### E. Compose `render/1`
Make the 153 lines a table of contents (the rule from the palette review):

```heex
<Layouts.app ...>
  <.editor_header ... />
  <.palette ... />
  <.score_view ... />
  <.editor_dialog dialog={@dialog} />
</Layouts.app>
```

The header and score view (the hook div and its `data-*` attributes, the score, the overlay and the measure controls) move to `EditorComponents`.

## Recommendation
Use C, B, D and E together, and skip A. The result:
- `EditorLive` keeps only `mount`, the hook list, `render` and `handle_info`, at about 150 lines;
- seven event modules, each 60–220 lines;
- four dialog LiveComponents;
- pure logic moved to `Music.Playback`, `ContextMenu`, `EditorCommands` and `Library`.

The order, each step its own reviewable change with `mix precommit` clean and no behaviour change:
1. Move the pure logic out.
2. Add the single `:dialog` assign and `close_dialog`.
3. Turn the form dialogs into LiveComponents.
4. Split the events into hook modules.
5. Group the assigns into structs.
6. Compose `render/1`.

The JS and the element ids stay the same throughout.
