# DrawMusic

Paint music onto a grand staff, hear it, and keep it: compositions are
stored per user in numbered versions, in any key, and download as MIDI
or print-ready SVG.

## Setup

The toolchain (Erlang, Elixir, Node) is pinned in `mise.toml`.

```sh
mise install
mise run setup     # deps, database, assets
mise run server    # http://localhost:4000
```

`mise run test` runs the tests; `mise run precommit` compiles with warnings
as errors, formats, runs Credo and the tests.

## Docs

- `plans/draw-music-plan.md`: the overall design and phases
- `plans/phase-3-rendering.md`: score engraving and display
- `THIRD_PARTY_NOTICES.md`: fonts and data we ship
