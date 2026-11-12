# PR 9b: `Editor.Palette`, a LiveComponent with its own keys

Step 9b of `plans/reexamine-all-components-and-sunny-pebble.md`. PR 9a split the
palette into function components; now it owns its events and its keyboard
shortcuts.

## Who owns what
The palette's state (`armed`, `row_kind`, `insert?`) stays in `EditorLive`, because
the score canvas needs it too: placing reads `armed` and `insert?`, the canvas's
`data-armed`/`data-insert` show it, the note menu uses `insert?`, and the canvas
itself disarms (Esc, right-click). That is shared state, so by our rule it lives in
the LiveView. The palette receives it as attrs, works out the next state with
`DrawMusicWeb.EditorPalette` (pure, unchanged), and reports the result.

## `DrawMusicWeb.Editor.Palette` (LiveComponent)
`lib/draw_music_web/live/editor/palette.ex` renders `PaletteComponents.palette/1`
(9a's function components, unchanged apart from `phx-target={@myself}` on
their buttons, passed down as a `target` attr).

**Inputs:** the palette's current attrs, plus `selection` (selected ids, for the
buttons that act on the selection when nothing is armed). The `below_mode` and
`trailing` slots stay as they are: the layout toggle and the save menu are
LiveComponents of their own.

**Events it handles** (all leave `EditorLive`): `toggle_mode`, `arm`, `arm_value`,
`arm_chord`, `single_notes`, `arm_tie`, `disarm` (the 0 key), `toggle_rest`,
`toggle_dot`, `set_accidental`, `toggle_insert`, `select_all`, `undo`, `redo`,
`open_settings`.

**What it reports** (`Editor.Intent`):
| Intent | From |
|---|---|
| `{:palette, %{armed: …, row_kind: …, insert?: …}}` (only the keys that changed) | arming, rest/dot/accidental with something armed, Insert/Overlay, 0 |
| `{:edit, fun}` / `{:edit, fun, :select}` | dot or accidental on the selection; a chord on the selection (selected) |
| `{:session, fun}` | select all |
| `{:mode, :edit \| :play}` | Edit/Play buttons and P |
| `{:history, :undo \| :redo}` | undo, redo and their keys |
| `{:open, :settings}` | the settings button |

`EditorLive` gains one `handle_info` each for `:palette`, `:mode` (today's
`toggle_mode` body: stop playback, close the menu, narrow the selection) and
`:history` (today's undo/redo bodies). `{:open, …}`, `{:edit, …}` and `{:session, …}`
are already handled.

New pure helpers in `DrawMusicWeb.EditorCommands`, so the component only builds
intents: `toggle_dots(ids)` (all dotted → undotted, else dotted, decided inside
the edit from the score) and `set_alter(ids, alter)` (notes only).

## Keys: the `.PaletteKeys` colocated hook
On `#palette` (in the component's render). It handles the palette's keys and
pushes them to its own component (`pushEventTo(this.el, …)`):
P (both modes), and in Edit mode only: 1–9, 0, R, ".", T, Insert, Ctrl+Z,
Ctrl+Shift+Z, Ctrl+Y, Ctrl+A. The editor's mode comes from a `data-mode`
attribute on `#palette`.

`index.js`'s `key()` stops handling those keys. It keeps Esc, the arrows,
Delete/Backspace, copy/cut/paste, the play keys and `?` (help) until PRs 10–11.

Shared code: a new `assets/js/score_editor/keyboard.js` holds `typing(e)`,
`dialogOpen()` (the dialog/help checks) and `keyId(e)`, used by both hooks.
`keys.json` stays the one list of keys (its test against `/help` is unchanged).

**Import check first:** add `assets/js` to esbuild's `NODE_PATH` in
`config/config.exs` and confirm a colocated hook can
`import {keyId} from "score_editor/keyboard"`. If it doesn't resolve, use a
relative import from the colocated output instead.

## Tests
- About 20 `render_hook(view, "arm" | "toggle_rest" | "undo" | …)` calls become
  `view |> element("#palette") |> render_hook(…)`, mostly through the
  `EditorHelpers`. Clicks on palette buttons follow `phx-target` unchanged.
- New `test/draw_music_web/live/editor/palette_test.exs` in `ComponentHostLive`:
  arming reports the new state; dot/accidental/chord with nothing armed report an
  edit on the selection; the mode buttons, undo/redo, select all and settings
  report their intents; chords are ignored for rests.
- `EditorCommands.toggle_dots/1` and `set_alter/1` get unit tests.

## Files (about 10)
`live/editor/palette.ex` (new), `components/palette_components.ex` and the
three `components/palette/*.ex` (the `target` attr), `live/editor_live.ex`,
`live/editor/intent.ex`, `editor_commands.ex`, `assets/js/score_editor/index.js`,
`assets/js/score_editor/keyboard.js` (new), `config/config.exs`, plus the tests.
If that is too many for one review, split it in two: **9b-1** the component and
its events (the keys still go through `index.js`, sent to `#palette` with
`pushEventTo`); **9b-2** the `.PaletteKeys` hook and `keyboard.js`.

## As built (2026-11-12)
- A LiveComponent's root must be a literal HTML tag, not a function component, so
  the toolbar's frame (`#palette`, its grid classes, the hook) is in
  `Editor.Palette.render/1`, which is now the palette's table of contents.
  `PaletteComponents.palette/1` is gone; `PaletteComponents` keeps `mode_switch/1`
  and `help_button/1`, the parts in both modes.
- No `NODE_PATH` change: esbuild already has `--alias:@=.`, so the hook imports
  `@/js/score_editor/keyboard`.
- `#palette` has `phx-target={@myself}`: LiveView tests only route a hook event to
  a component through it (the browser's `pushEventTo(this.el, …)` doesn't need it).
- `EditorLive` keeps `disarm` and `open_settings`, because the score canvas still
  sends them (Esc, a right-click while placing, the opening tempo marking) until
  PR 11.
- The component ignores its edit events in Play mode, as `EditorLive` did, and
  `EditorLive` also ignores `{:palette, …}` and `{:history, …}` in Play mode.

## Verification
- `mix precommit`.
- You check in the browser, both modes: every palette button and every palette
  key (1–9, 0, R, ., T, Insert, Ctrl+Z/Y/A, P), and that the canvas keys (Esc,
  arrows, Delete, copy/paste) still work, with nothing handled twice.
- `/help`: no keys change, so no cheat-sheet changes.
