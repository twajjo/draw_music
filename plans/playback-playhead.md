# Playback playhead + follow (2026-10-27)

## Context
During playback, show a red vertical line at the current playback point and keep it in view in both score layouts.

## Decisions
- Strip: page-turn in jumps (line past ~85% of the visible width, or off-screen left → line at ~20%).
- Page: when the line moves to a system not fully visible, scroll that system into view.
- Following continues even if the user scrolls manually.

## Changes
- `PlaybackPayload`: add `from` (start tick) and `seconds_per_tick`; `EditorLive.start_playback/1` fills them.
- `audio.js`: `onTick(seconds | null)` each frame (loop-aware); null on stop/end.
- `playhead.js` (pure): tick → {system, x} via the geometry payload and `xAt`.
- `index.js`: draws `<line class="playhead">` in `#score-overlay`, follows it (strip: `#score-paper` scrollLeft; page: window scroll).
- `app.css`: `.playhead` stroke `var(--color-error)`.
- `/help`: Playback entry.
- Tests: `editor_play_test.exs` checks `from` and `seconds_per_tick`.

## Verification
`mix precommit`; manual: strip + page, from a selection, pause/rewind/loop, line in step with lit notes.
