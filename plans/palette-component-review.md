# Review: the palette component (from the Phase 5 code review)

Recorded 2026-11-04; **Phase 8 work**. The palette has not been broken up yet.

## The problem
`lib/draw_music_web/components/palette_components.ex` is 713 lines. Its `palette/1` is a single 389-line block of HEEx (lines 84–472) holding every part of the toolbar:
- the Edit/Play switch;
- the note and rest lengths, the rest toggle and the dot;
- tie and the chords menu;
- the Insert/Overlay switch;
- select all, undo and redo;
- all eight transport buttons;
- the playback-instrument picker;
- help, plus the `below_mode` and `trailing` slots.

Only `piece/1` and `arrows/1` are factored out. A reader has to scroll through the whole blob to find one control. Most buttons also repeat the same markup: `btn` classes, `title`, `aria-pressed` and `phx-click`.

## Principle
A component is composed from sub-components, each with one job and a name that says what it is. `palette/1` should read like a table of contents for the toolbar.

## Proposed structure
`palette/1` stays the grid frame and composes:

```heex
<.palette_frame>
  <.mode_switch editor_mode={@editor_mode} />
  <.edit_tools :if={@editor_mode == :edit} ... />
  <.transport :if={@editor_mode == :play} ... />
  <.help_button />
</.palette_frame>
```

- **`mode_switch/1`:** the Edit/Play buttons.
- **`edit_tools/1`** (Edit mode's two rows), composed of:
  - `length_row/1`: the note or rest values (`piece/1`), with `rest_toggle/1` and `dot_button/1`;
  - `tie_button/1` and `chords_menu/1` (the chord qualities and degrees, and Single notes);
  - `placing_toggle/1`: Insert or Overlay;
  - `history_tools/1`: select all, undo and redo.
- **`transport/1`** (Play mode), composed of:
  - one generic `transport_button/1` (id, title, icon or arrows, event, disabled), used for rewind, back line, back measure, stop, play, skip measure, skip line and loop, instead of eight hand-written buttons;
  - `instrument_picker/1`: the select and its "Set … version Instrument" button.
- **`help_button/1`.**
- **A shared `tool_button/1`:** the common button shell (classes, `title`, `aria-pressed`, `disabled`, click). The specific buttons above are built on it, so the classes live in one place.
- **Helpers:** `play_label`, `play_icon`, `play_title` and `chords_label` stay next to the sub-component that uses them.

## Modules
Split the file, which is over the 500-line limit, so each module is one area:
- `PaletteComponents`: `palette/1`, `mode_switch`, `help_button`, `tool_button`, `save_menu`;
- `Palette.EditTools`: the length row, chords, tie, placing and history;
- `Palette.Transport`: the transport and the instrument picker;
- `Palette.Glyphs`: `piece/1` and the glyph box maths (`glyph_view_box`, `glyph_size`, `vertical_range`, `@note_range`).

Public components go first and private helpers last in each module. Each component gets `attr` declarations and an `@spec`.

## Keep
- Every element id (`palette-*`, `playback-instrument*`) stays the same, so the tests and JS don't change.
- The rendered markup stays the same; this is a readability refactor only.
- `mix precommit` must stay clean, and the user checks the palette in the browser in both modes.

## Same rule elsewhere
`EditorLive.render/1` has a 153-line HEEx block. Review it the same way during the `editor_live.ex` size review. No other component block is over about 120 lines.
