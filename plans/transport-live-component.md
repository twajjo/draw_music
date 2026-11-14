# PR 10: `Editor.Transport`, a LiveComponent that owns playback

Step 10 of `plans/reexamine-all-components-and-sunny-pebble.md`. The play
controls (`Palette.PlayControls`, from 9a) still send their events to
`EditorLive`, which keeps the playback state, and the external `ScoreEditor`
hook (`index.js`) runs the audio, the playhead and the play keys. This PR
gives playback one owner.

## What is shared, and how it is split
- **The audio engine** (`audio.js`) plays the score, but also sounds a note
  while placing or dragging (the canvas) and auditions a clicked chord. There
  must be one engine, so `audio.js` gains `sharedAudio()`, a single instance
  that both hooks use. The transport sets its callbacks (state, ended, tick).
- **The playhead** is drawn on the score, from the score's geometry, so it
  stays the canvas's. The transport knows only *when* playback is: on each tick
  it sends a `score:playhead` window event with the tick (or none). The canvas
  draws the line there and scrolls to it. The idle playhead in Play mode
  (`data-play-start`) stays as it is.
- **The playback instrument** is also the instrument for the canvas's drag
  tones. It is loaded into the shared engine, so loading it moves to the
  transport (`data-instrument` moves from the canvas to the transport's root).
- **Skipping while playing** needs the measure and line starts. The server now
  sends them with the `skip` push, so the transport hook needs no geometry.

## `DrawMusicWeb.Editor.Transport` (LiveComponent)
`lib/draw_music_web/live/editor/transport.ex` renders `Palette.PlayControls` (its
buttons get `phx-target`) inside its root, `<div id="transport" class="contents"
phx-hook=".Transport">`. It is **mounted in both modes**: in Edit mode its root is
empty, but it stays mounted so the loop setting and the playback instrument last
across mode switches, as they do today. `Editor.Palette` gets a `:play_controls`
slot for it in place of `<.play_controls>`, so the palette doesn't need to know
about playback.

**Owns:** `playback` (`:idle | :loading | :playing | :paused | :rewound`), `loop?`,
`playback_instrument` and its `InstrumentSource`. These assigns leave `EditorLive`.

**Inputs:** `score`, `ctx`, `selection`, `engraved` (for skip points),
`editor_mode`, `instrument` (the version's), `instrument_options`.

**Events it handles** (all leave `EditorLive`): `play`, `rewind`, `skip`, `stop`,
`toggle_loop`, `playback_state`, `playback_ended`, `set_playback_instrument`,
`use_playback_instrument`.

**Its own stop rules, in `update/2`**, replacing `EditorLive`'s `stop_playback`
calls (it compares the new inputs with the last ones):
- the score changes (any edit, undo, settings, transpose): stop;
- the editor goes to Edit mode: stop;
- the selection changes while paused or rewound: stop, so Play starts the new
  span (today's `drop_paused`);
- the version's instrument changes: playback follows it (today's
  `assign_instrument`).

**What it reports** (`Editor.Intent`):
| Intent | From |
|---|---|
| `{:session, fun}` | skip before playing (moves the start point = selects); Esc in Play mode with nothing sounding (clears the selection) |
| `{:instrument, program}` | "Set selection to version Instrument" (the editor marks the score touched and stores it) |
| `{:flash, :error \| :info, msg}` | "Nothing to play here."; the instrument fell back to the synth |

## Keys and JS: the `.Transport` colocated hook
On `#transport`, as short glue:
- the `play`/`pause`/`resume`/`rewind`/`skip`/`loop`/`stop`/`audition`
  handleEvents, on `sharedAudio()`;
- the play keys, in Play mode: Space, Home, L and Esc, with
  `pushEventTo(this.el, …)`. Pause and Stop act at once, before the server
  replies, as today, via its own buttons' clicks, not a document listener;
- the first-gesture unlock of audio;
- loading the instrument from `data-instrument`;
- the `score:playhead` window events.

The skip-target maths (`skipTarget(starts, anchors, position, back)`) moves to a
small pure module, `assets/js/score_editor/transport.js`, so the hook stays glue.
`audition` stays an `EditorLive` event (the canvas sends it) until PR 11, but its
sound goes to the shared engine.

`index.js` loses the audio setup, the play handleEvents, `pauseNow`, `playKey`,
`onTransport`, `skip` and `loadInstrument`. It listens for `score:playhead`, and
uses `sharedAudio()` for drag tones and to check whether something is sounding.

## `EditorLive` after this PR
It loses the 9 events above, the playback assigns, and the playback helpers
(`start_playback`, `skip_start`, `playback_state`, `loaded`, `stop_playback`,
`drop_paused`, `stop_unless_playing_mode`, `assign_playback_instrument`). It gains
one `handle_info` for `{:instrument, program}`. `audition` stays.

## Tests
- `editor_play_test.exs` and `editor_mode_test.exs`: 14 `render_hook(view, "play"…)`
  calls become `element("#transport") |> render_hook(…)`. The 31
  `assert_push_event` checks are unchanged, because a component's pushes still reach
  the view.
- New `test/draw_music_web/live/editor/transport_test.exs` in `ComponentHostLive`:
  the play/pause/resume/rewound states; loop; skip before playing reports a selection,
  while playing it pushes `skip` with the points; nothing to play flashes; the stop
  rules (a new score stops; a new selection drops a paused span; Edit mode stops); a
  new version instrument becomes the playback one; "Set … version Instrument" reports
  it.
- A small JS-free check that `#transport` stays mounted in Edit mode.

## Files
`live/editor/transport.ex` (new), `live/editor/palette.ex` (the slot),
`components/palette/play_controls.ex` (`target`), `live/editor_live.ex`,
`live/editor/intent.ex` (`:instrument`), `assets/js/score_editor/audio.js`
(`sharedAudio`), `assets/js/score_editor/transport.js` (new),
`assets/js/score_editor/index.js`, plus tests: about 8 source files.

## Risks to check in the browser
- Pause and Stop still feel instant (they act before the server replies).
- The playhead follows playback in both layouts, and waits at the start point
  when idle.
- Drag tones and audition still sound, on the chosen playback instrument.
- The playback instrument and Loop survive switching to Edit and back.

## As built (2026-11-13)
- The transport gets the instrument options itself
  (`LibraryComponents.instrument_options/0`, at mount), so `EditorLive` no
  longer keeps them.
- Behaviour change, from the browser check: **before playing, Stop (and Esc)
  and Rewind go back to the beginning of the score**. They clear the selection
  (`{:session, &Session.clear_selection/1}`), so the idle playhead and the
  next Play start there. Before, they left the start point where a skip had
  moved it. Playing or paused, they work as before. Esc now always sends
  `stop`; the button titles and `/help` say so.
- The `skip` push keeps `by` and adds `starts`.
- A new version instrument doesn't stop playback by itself: it can only change
  in Edit mode, where playback has already stopped.
- `ComponentHostLive` accepts `{:host_attrs, changes}`, so a component test can
  give the component new inputs as a page re-render would (the stop rules).
- `EditorLive` shrank from 1125 to 919 lines; `index.js` from 1039 to 954.

## Verification
- `mix precommit`, then the JS bundle builds.
- You check in the browser, Play mode: Play/Pause/Resume, Rewind, Stop, the
  four skips (idle and while playing), Loop, the instrument picker and its "Set"
  button, Space/Home/L/Esc, the playhead in Page and Strip. Edit mode: the drag
  tones, and that the playback instrument and Loop are kept.
