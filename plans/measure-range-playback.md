# PR 10b: playing a range of measures, and ⏭ to the end

A behaviour PR on top of PR 10's `Editor.Transport`. The play palette gets:
- **Measures From/To**, a range selection by measures that redefines the
  bounds of the piece for playback;
- a **Whole piece** button that resets them;
- **⏭ to the end** (key: End), the opposite of Rewind.

## The model
- **The bounds** (`DrawMusic.Music.PlayRange`, pure): `from`..`to` in ticks,
  covering measures `first`..`last` of `count` (numbered from 1, both included).
  - They come from the chosen measures, or, if none were chosen, from the
    selection, as today (`Playback.span/3`).
  - With nothing selected, they are the whole piece, 1..N.
  - Play, Loop, Rewind, Stop, the four skips and ⏭ all work inside them.
- **The play cursor** is where Play starts, a tick from `from` to `to`. It is
  the transport's own state, separate from the selection, so moving it
  (skips, ⏭, Stop) never changes the chosen measures.
  - Unset, it is the start of the bounds.
  - It is reset when the bounds change, on Stop and Rewind, and when a
    non-looped span finishes.
- **Chosen measures** are kept as `{first, last, ids}`. Choosing them selects
  those notes and rests (highlighted, as a range selection by measures). They
  stay the bounds while the selection is still exactly those ids. Any other
  selection (a click, a drag) replaces them.

## Controls (Play mode, the palette's second row)
`Measures [From ▾] to [To ▾] [Whole piece]`, after the instrument picker and
its "Set" button.
- **From** lists 1..N. **To** lists From..N, so From ≤ To; From = To plays
  one measure.
- **The lists always show the bounds:** the chosen measures, or the measures
  the selection reaches into, or 1..N.
- **They can be changed only when not playing:** stopped, paused, or at the
  end. While playing they are disabled. Changing them while paused drops the
  paused span. Play must be pressed to play the new bounds.
- **Whole piece** clears the selection: bounds 1..N. It is disabled while
  playing.

## Buttons and keys
| Control | Before playing | Playing | Paused |
|---|---|---|---|
| Play (Space) | plays from the cursor to the end of the bounds; at the end: Loop off → "Nothing to play here.", Loop on → from the start of the bounds | pause | resume |
| ⏮ Rewind (Home) | cursor to the start of the bounds | restart at the start of the bounds | back to the start, waits (Play) |
| ⏹ Stop (Esc) | cursor to the start of the bounds | stop, cursor to the start | stop, cursor to the start |
| ⏪ ⏩ ⏪⏪ ⏩⏩ | move the cursor, inside the bounds | jump, inside the bounds | jump, inside the bounds |
| ⏭ To the end (End, new) | cursor to the end of the bounds | Loop on → as Rewind; Loop off → stop at the end | stop at the end |

Loop repeats the whole of the bounds, even when Play started at the cursor
part-way in.

PR 10's "before playing, Stop and Rewind clear the selection" becomes "move
the cursor to the start of the bounds". With nothing chosen, that is still the
beginning of the piece. Clearing the bounds is now the Whole piece button's job.

## How it's built
- `PlayRange` (new, pure): `of_selection/3`, `measures/4`, `ids/3`,
  `skip/4` (a skip kept inside the bounds) and `start/2` (the cursor kept
  inside the bounds).
- `Editor.Transport`:
  - new assigns `measures` and `cursor`; the bounds are worked out in Play
    mode;
  - new events `set_measures` (the From/To form), `whole_piece` and `to_end`;
  - Play sends the whole of the bounds plus `at` (seconds into them for the
    cursor), so Loop goes round the bounds;
  - the idle playhead's place (`data-play-start`) moves from the score
    element to `#transport`, because the cursor is the transport's now.
- `PlaybackPayload` gets `at`. `audio.js`'s `play(events, span, loop, at)`
  starts `at` seconds in.
- The `.Transport` hook:
  - the End key;
  - after each update, a `score:play-start` window event, from which the
    score draws the idle playhead. The editor opens in Edit mode, where there
    is no playhead, so the first update in Play mode is in time.
- `index.js` takes the idle playhead's place from `score:play-start`, not
  from its own `data-play-start`.
- `EditorLive` loses `data-play-start` and `play_start/1`.
- `PlayControls`: the ⏭ button and the `measure_range` sub-component.
- `/help` (`Shortcuts`) and `keys.json`: End, ⏭, the measure lists, Whole piece.

## Tests
- `PlayRange` unit tests: bounds from measures and from the selection; a skip
  kept inside the bounds; the cursor kept inside the bounds.
- `transport_test.exs`:
  - choosing measures selects their ids;
  - the lists are disabled while playing;
  - Play from the cursor sends `at`;
  - ⏭ in each state;
  - Play at the end with Loop off flashes, and with Loop on starts at the
    start of the bounds;
  - Whole piece clears the selection;
  - the skips stay inside the bounds.
- `editor_play_test.exs`: one test from start to finish (measures 2–3, Play
  sends only those, ⏩ stays inside them, Whole piece gives the whole piece
  again); the `data-play-start` checks move to `#transport`.

## Files (about 12)
`music/play_range.ex` (new), `live/editor/transport.ex`,
`components/palette/play_controls.ex`, `playback_payload.ex`,
`live/editor_live.ex`, `shortcuts.ex`, `assets/js/score_editor/{audio.js,
index.js, keys.json}`, plus tests.

## As built (2026-11-13)
- With one note selected, the bounds run from that note to the end (as
  Play already did), so ⏪ before playing no longer goes back past the
  selected note. Choose measures, or Whole piece, to move freely.
- The measure lists use `<.input type="select">`. To lists From..N. If From
  passes To, the server sets To = From (`PlayRange.measures/4` clamps it).
- The bounds are worked out only in Play mode (`range` is nil in Edit), so
  editing a long score doesn't pay for walking it on every render.
- `transport.ex` is 578 lines, about 150 of them the colocated hook. That is
  over the ~500-line mark, and a candidate for a split.

## Verification
- `mix precommit`, then the JS bundle builds.
- You check in the browser:
  - choose measures (they highlight, To can't go below From);
  - Play and Loop over them;
  - the skips, Stop, Rewind and ⏭ inside them;
  - ⏭ then Play, with Loop off and with Loop on;
  - Whole piece;
  - the lists locked while playing.
