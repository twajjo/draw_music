# Tidy the `draw_music_web` root

The root of `lib/draw_music_web` should hold only Phoenix's own files and
the auth code, as a generated Phoenix app does. Modules written for
DrawMusic go in folders by subject, the way `lib/draw_music` is organised
(`music/`, `engraving/`, `library/`): structs live beside the code that
uses them.

Decided 2026-11-25, by subject rather than types/helpers.

## Stays in the root

`endpoint.ex`, `router.ex`, `telemetry.ex`, `gettext.ex`, `user_auth.ex`,
and the plugs `health_check.ex` and `samples_static.ex`. Also the existing
folders `components/`, `controllers/` and `live/`.

## Moves

Each module is renamed to match its folder. Every PR is a move only: the
renames and their references, nothing else.

1. **`help/`**: `Shortcut` → `Help.Shortcut`, `Shortcuts` (and
   `shortcuts/`) → `Help.Shortcuts` (`Help.Shortcuts.Placing`, ...),
   `Credit` → `Help.Credit`.
2. **`score/`**: `ScoreSvg` → `Score.Svg`, `ScoreExport` → `Score.Export`,
   `ScorePiece` → `Score.Piece`, `PlaybackPayload` →
   `Score.PlaybackPayload`, `InstrumentSource` → `Score.InstrumentSource`.
3. **`editor_support/`, the palette and placing**: `Armed` →
   `EditorSupport.Armed`, `EditorPalette` → `EditorSupport.Palette`,
   `EditorPlacement` → `EditorSupport.Placement`, `PlacementTarget` →
   `EditorSupport.PlacementTarget`, `EditorGeometry` (and
   `editor_geometry/`) → `EditorSupport.Geometry`
   (`EditorSupport.Geometry.ArmedPayload`, ...).
4. **`editor_support/`, the rest**: `EditorCommands` →
   `EditorSupport.Commands`, `EditorSettings` → `EditorSupport.Settings`,
   `EditorSaving` → `EditorSupport.Saving`, `ContextMenu` →
   `EditorSupport.ContextMenu`, `TempoForm` → `EditorSupport.TempoForm`,
   `TempoTarget` → `EditorSupport.TempoTarget`, `ReadingAid` and
   `ReadingAids` → `EditorSupport.ReadingAid(s)`, `VersionLookup` →
   `EditorSupport.VersionLookup`.
5. **`import/`**: `ImportPanel` → `Import.Panel`.

(`EditorSupport`, not `Editor`: the editor's LiveComponents already use
`DrawMusicWeb.Editor.*` in `live/editor/`.)

The plans and memories that name a moved module are updated in the same
PR as the move.

## From now on

A new DrawMusic-specific web module goes into the folder for its subject
(a new subject gets a new folder), never in the root.

## Status

- **PR 1, `help/` (in review):** `Help.Shortcut`, `Help.Shortcuts` (and its
  three area modules) and `Help.Credit`; the shortcuts test moved to
  `test/draw_music_web/help/`. Test files follow their modules' folders.
