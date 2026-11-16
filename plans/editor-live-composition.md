# EditorLive: a composed page and grouped state (PR 12)

After 11c, `EditorLive` (635 lines) handles no score events, but its
`render/1` is still one 170-line template, and its state is a dozen loose
assigns. PR 12 is two small PRs, both refactors with no change in behaviour.

## 12a: `render/1` reads like a table of contents
A new `DrawMusicWeb.EditorPage` module of function components (no events of
their own, so function components are right):

- `editor_header/1`: the title row, the details button, the version picker
  or "Unsaved" badge, and the SVG/MIDI downloads (`downloads/1`). `credits/1`
  and `export_path/2` move with it.
- `score_paper/1`: the paper around the score, with the layout's classes, as
  a slot.
- `open_dialog/1`: the one dialog or menu open, picked by pattern matching on
  `@dialog` (`{:menu, menu}`, `:details`, `:save_as`, `{:tempo, target}`,
  `:settings`, `{:transpose, key}`, nil), in place of six `:if` blocks.

`render/1` becomes the header, the palette (with its transport, layout toggle
and save menu slots), and the paper holding the canvas, the guard, help,
`open_dialog` and the preferences panel. About 110 lines leave `EditorLive`.

## 12b: the loose assigns become structs
- `:palette`, a `%DrawMusicWeb.Editor.PaletteState{armed, row_kind, insert?}`,
  for `armed`, `row_kind` and `insert?`. The `{:palette, changes}` intent
  becomes `struct(palette, changes)`.
- `:drawing`, a `%DrawMusicWeb.Editor.Drawing{engraved, pieces,
  geometry_json, loading?, key_suggestion}`, for what `lay_out/4` builds.
- `:extras`, a `%DrawMusicWeb.Editor.VersionExtras{tempo_text, instrument}`,
  for what is saved beside the score.

`editor_mode`, `dialog`, `session`, `composition`, `version`, `path` and
`preferences?` stay as they are. The tests that read `assigns(view).armed`,
`.insert?` and `.instrument` read them through the new structs.

## Afterwards
PR 13, the function-order sweep (`editing.ex`, `transport.ex` and the rest),
then measure locks.
