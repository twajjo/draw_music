# Select all (2026-10-27)

## Context
Besides the rubber band, a way to select every note and rest for editing.

## Changes
- `EditorLive`: `select_all` event → every id from `Editing.select_range(score, ctx, 0, Timeline.end_tick(score, ctx))`, via `reselected(&Session.select(&1, ids, false))`.
- Hook: `Ctrl+A` in `keys.json`; `key()` sends `select_all` (Edit mode only).
- Palette: `#palette-select-all` button next to Undo/Redo.
- `/help`: Editing entry.
- Tests: `editor_select_test.exs` — key event and button select every note and rest; delete after it empties the score.

## Verification
`mix precommit`; manual: Ctrl+A then copy/paste, transpose, delete.
