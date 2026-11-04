# Tempo changes within a piece (2026-10-27)

## Context
A version has one tempo (`Version.tempo_bpm`), and import keeps only a file's first tempo event. The
imported Toccata (69 tempo events: section tempos at bars 4, 22, 30; quick dips in bars 1–3;
gradual runs in 8–9, 127–128, 141–142) therefore plays at 28 BPM throughout. Tempo changes are part
of the music: store them, play them, draw them, edit them, import and export them.

Decided: steady changes are ♩ = N marks; a run of small same-direction steps becomes one
"rit." / "accel." line, edited as a single item.

## Model
- `DrawMusic.Music.TempoChange` (embedded): `id`, `tick` (from the score's start), `bpm`, and for a
  gradual change `to_tick` + `to_bpm` (tempo moves linearly from `bpm` to `to_bpm` over the span).
- `Score` gains `embeds_many :tempos`. The score is JSON on the version: no migration.
- `Version.tempo_bpm` stays the tempo at the start. Settings' field becomes "Starting tempo (BPM)".
- Ticks are absolute, so a time-signature re-bar leaves them alone. Inserting or deleting a bar
  moves the later changes with the music; Insert-mode note shifts (one staff) don't.

## Timing — `DrawMusic.Music.TempoMap` (new, pure)
- `seconds(score, ctx, from_tick, to_tick)`: piecewise over the changes; a ramp integrates its
  linear BPM exactly (log form).
- `Playback.events/3` and the span use it in place of `Playback.seconds/2` × tempo.
- Payload: `seconds_per_tick` is replaced by `anchors: [{seconds, tick}]` (each change, plus each beat
  inside a ramp). `playhead.js` interpolates between anchors.

## Import / export (`midi_codec.ex`)
- Read every FF 51 with its quantized tick. First → `tempo_bpm`. Drop changes equal to the tempo in
  force.
- Group: 3+ consecutive changes, each ≤ 2 beats after the last, all the same direction, each step
  ≤ 15% → one gradual change. Everything else → a mark.
- Export writes each mark, and a gradual change as one tempo event per beat across its span.
  Round trip: export → import gives the same marks and ramps back.

## Drawing (engraving + `score_components.ex`)
- Marks above the treble staff at their tick's x: Bravura metronome note + "= 90".
- Gradual: "rit." / "accel." then a dashed line to `to_tick`, ending in "♩ = 45".
- Crowded marks (bars 1–3) stagger onto a second row; systems get the headroom they need.
- Each has a DOM id (`tempo-<id>`) and is selectable like notes.

## Editing (drawn means editable; same rules as notes)
- Click selects; Delete removes; Ctrl+Z undoes (tempos are in the score, so history covers them).
- Right-click a note or rest → "Tempo change here…". Right-click a mark → "Edit tempo…" (BPM; for a
  gradual change, end BPM; switch steady ↔ gradual) and "Delete".
- Drag a mark sideways; it snaps to note and rest columns. Drag a gradual line's end to resize it.
- Select all (Ctrl+A) includes them.

## Also
- `/help`: entries + diagrams for marks, gradual lines, adding/editing/moving.
- Playhead follows the varying speed (via anchors).
- Re-import the Toccata (Replace) once done.

## Status (2026-10-27)
Both phases built; `mix precommit` passes (474 tests). Import also detects the start key from the
notes (Krumhansl–Schmuckler, `KeyDetection`). Not yet checked in a browser. Needs `mix ecto.migrate`
(tempo range 5–400). The Toccata imports as D minor, 28 BPM, 52 changes (4 rit./accel.).

## Phases
1. Model, TempoMap, playback, import/export: it sounds right. Tests: TempoMap math (steady and ramp),
   playback times across a change, import grouping on a synthetic file, export→import round trip.
2. Drawing and editing. Tests: marks rendered with ids, add/edit/delete/move events, undo, measure
   insert/delete moves later marks.

## Verification
`mix precommit` per phase; manual: re-import the Toccata, listen to bars 1–4 and 8–9, watch the
playhead keep in step, edit/move/delete a mark and a rit. line, export `.mid` and re-import.
