# Resume Phase 2: Music domain + MIDI

## Context
Phase 1 is committed (`master` = 418a22d). Phase 2 is in progress in the
undescribed jj change `wulzyvpx` on top of `master`. Already written:
- `lib/draw_music/music/*` (15 modules: Score, Measure, Note, Rest, Duration,
  Pitch, Accidentals, Beaming, Stems, Chords, Timeline, Editing, Transpose,
  Playback, Context)
- `lib/draw_music/midi_codec.ex`, a wrapper around `ex_midi` (dep added in mix.exs/lock)
- `Version.score` changed from `:map` to `embeds_one Score`, plus a pickup-length validation
- `plans/draw-music-plan.md` updated: accidental rules, the libraries/licensing
  section, and the `midi/` dir marked superseded
- Tests: only `test/draw_music/music/duration_pitch_test.exs` and `test/support/music_helpers.ex`

## Remaining steps
1. `mix compile --warnings-as-errors` and `mix test` to see where the in-progress code stands.
2. Add functionality-only tests (per the memory rule):
   - Editing: ties across bars, `:measure_full`, range limits, transpose and shift
   - Timeline
   - Beaming and Stems
   - Accidentals (the display rules in the plan)
   - MidiCodec round trip, using `MusicHelpers`
   - Version changeset: score embed + pickup validation
3. Fix whatever those tests turn up.
4. `mix precommit` clean, then `jj describe -m "Music domain + MIDI codec (ex_midi)"` with
   the Co-Authored-By trailer, and move `master` to the change.

## Verification
`mix test` passes; `mix precommit` is clean; `jj log` shows phase 2 described and `master` moved onto it.
