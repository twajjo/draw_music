# DrawMusic: grand-staff music painter with MIDI storage

## Context
`draw_music` is a fresh Phoenix 1.8.15 / LiveView 1.2 / Postgres scaffold with nothing app-specific yet. Users will paint notes and rests from a palette onto a grand staff, using a grid. The app:
- creates a composition by picking a key, time signature and tempo;
- sounds pitches while you pick a position, and plays the piece back;
- keeps per-user compositions with numbered versions in Postgres;
- downloads and uploads Standard MIDI Files;
- exports the sheet as SVG.

Pedagogical reference: *Music Moves for Piano, Read & Write Book 1* (Marilyn Lowe / Edwin Gordon's Music Learning Theory). The supplied PDF is a 20-page excerpt. Relevant ideas from it:
- key signatures taught as a "DO" or "DO/LA" signature;
- meters described by macrobeat/microbeat (duple: quarter-note MB; triple: dotted-quarter MB);
- intervals and triads on the staff;
- I and V/V7 patterns in major and harmonic minor;
- transposition.

## Decisions (from interview)
- **Auth/storage:** `phx.gen.auth` users. Each user has compositions, and each composition has numbered versions. Users can add, rename, update and delete them.
- **Editor saves:** **Save** (overwrite current version) · **Save as new version** · **Save as new composition** (name prompt + collision check).
- **Import:**
  - The name comes from the MIDI track name (FF 03), falling back to the filename, and the user can edit it.
  - On a name collision the user chooses: **Cancel** · **Replace** (delete all versions, store as v1) · **New version** · **New composition with a different name** (re-checked).
- **Rendering:** server-rendered SVG function components with **Bravura** (SMuFL) glyphs, on a **grid**: x = ticks (proportional spacing, zoomable), y = diatonic staff positions.
- **Range:** a continuous pitch grid from A0 to C8. It covers above the treble staff, the treble staff, the gap between the staves, the bass staff, and below it.
  - The drawing staff comes from the clicked position: inside a staff, that staff; above or below, the nearest staff with ledger lines; in the gap, the closer staff.
  - No 8va signs.
  - An ↑/↓ move or paste that would push any note outside A0–C8 is rejected for the whole selection, with a message.
- **Notation:**
  - whole through 64th notes and rests, from the palette;
  - dots;
  - ties: mouse-down on the source note, mouse-up on the target, forward or backward;
  - accidentals;
  - chords by stacking notes at the same position or from a catalog;
  - automatic beaming.
- **Placing notes:**
  - Pick a value in the palette, then move over the staff. Each new line or space plays a brief tone at that pitch.
  - **Shift** = sharp, **Ctrl or Alt** = flat (on every platform).
  - **Click** places the note.
- **Modes:**
  - **Edit:** rubber-band selection, copy and paste, ↑/↓ moves the selection one diatonic step, ←/→ moves it one beat (the denominator unit).
  - **Play:** Play/Pause and Rewind. Clicking a note plays it and sets the start point. A drag-selected range plays just that range.
  - Selections cover both staves.
- **Tempo:** defaults to 100 BPM and is editable.

## Notation rules to implement (research: Wikipedia Stem/Beam, teoria.com, musictheory.net, SMuFL)
- **Stems:**
  - Up below the middle line, down on or above it. Up-stems attach on the right of the notehead, down-stems on the left.
  - Length is about one octave (3.5 spaces). Notes on ledger lines more than an octave from the middle line get stems that reach the middle line.
  - A chord takes one stem; its direction comes from the note farthest from the middle line. Seconds put the upper note on the right.
- **Beams:**
  - Only 8th notes and shorter. The number of beams equals the number of flags.
  - Group by beat: quarter in simple meters, dotted quarter in compound. In 4/4, eighths may be beamed per half bar.
  - Beams never cross bar lines; rests break groups.
  - The whole group shares one stem direction, set by its highest and lowest notes.
  - The beam slants with the contour, limited to 1 space.
  - Secondary beams break at sub-beats; a lone short note gets a fractional beam.
- **Key signatures:**
  - Sharps go in the order F C G D A E B, flats in B E A D G C F.
  - Their positions on each clef come from the SMuFL/standard tables.
  - Minor is relative: same signature, mode flag.
- **Accidentals** (signs before individual notes, as opposed to the key signature):
  - Notes store their absolute alteration. The renderer derives the signs.
  - A sign (♯ ♭ ♮ 𝄪 𝄫) shows only when the note's alteration differs from what's in effect at that point: the key signature, overridden by any earlier accidental on the same staff position, staff and bar.
  - So ♮ appears only when the note would otherwise read sharp or flat.
  - An accidental lasts until the bar line. A tied continuation into the next bar shows no sign.
  - No courtesy (parenthesized) accidentals unless requested later.
- **Rests:**
  - A whole rest hangs from the 4th line and also stands for a full empty bar in any meter.
  - Rests sit centered on their staff.
- **Ties and accidentals:** a tied note keeps its accidental into the next bar without repeating it. Courtesy accidentals, in parentheses, go on the first same-letter note of the following bar.
- **Key table (sf → major/minor):**
  - 0: C/a
  - Sharps: +1 G/e, +2 D/b, +3 A/f♯, +4 E/c♯, +5 B/g♯, +6 F♯/d♯, +7 C♯/a♯
  - Flats: −1 F/d, −2 B♭/g, −3 E♭/c, −4 A♭/f, −5 D♭/b♭, −6 G♭/e♭, −7 C♭/a♭
  - Optional book-style label: "DO is ___ / LA is ___".
- **Bravura assets:** `steinbergmedia/bravura` (SIL OFL 1.1). Use `redist/woff/Bravura.woff2` (323 KB) and `redist/Bravura.json` (metadata) at build time, and ship `OFL.txt`.
- **Sources consulted:** Wikipedia (Stem, Beam, Key signature, Accidental), teoria.com Reading Music, the SMuFL spec, and the midimusic.github.io SMF spec. musictheory.net renders its lessons in JavaScript, so its content couldn't be fetched. tonedear.com is an ear-training site, which suggests a later feature: interval and chord recognition drills.
- **Glyphs:** SMuFL code points come from Bravura's `glyphnames.json`, with spacing from `bravura_metadata.json` (`engravingDefaults`) for staff-line thickness, stem thickness, beam thickness and ledger-line extension.

## Libraries and licensing (decided 2026-10-21)
**Use off-the-shelf libraries; don't re-invent them.**
- **MIDI files:** `ex_midi` (hex, Apache-2.0), wrapped in one module of ours. Its read/write API takes file paths: uploads are temp files, and downloads go through a temp file.
- **Browser audio:** Tone.js (MIT) for placement tones and scheduling, and smplr (MIT) for instruments.
  - Splendid Grand Piano (public domain).
  - General MIDI soundfonts from the MusyngKite set (CC BY-SA 3.0). `version.instrument` (GM 0–127) maps 1:1 to them.
- **Samples are self-hosted.** `mix samples.fetch` downloads them into a gitignored `priv/static/samples/`, together with each set's license file. `mix setup` runs it.
  - Default set: Splendid Grand Piano plus about 12 GM instruments (electric piano, harpsichord, organ, acoustic guitar, violin, cello, flute, clarinet, trumpet, choir, marimba…).
  - More can be added in the task config. The picker shows unfetched instruments as "not installed".
- **Not used:** midiex (live MIDI ports, maybe later for keyboard input), midi_synth / TuningFork (they make sound on the server, which users can't hear), @tonejs/midi (files are handled on the server).
- **Attribution:**
  - A Credits page (footer link) and `THIRD_PARTY_NOTICES.md`.
  - MusyngKite needs credit plus a license link.
  - Bravura ships with `OFL.txt`.
  - Keep MIT notices.

## Architecture

### Persistence: `DrawMusic.Library`
- `mix phx.gen.auth Accounts User users --live` (this adds `Scope`; every context function takes it).
- **Hierarchy:** Composition → Key → Version (built).
  - `compositions`: `user_id`, `name` (citext, unique per user), `subtitle`, `composer` (may differ from the user, e.g. a by-ear transcription), `arranger`, `lyricist`, `copyright`, `notes`.
  - `composition_keys`: `composition_id`, `sf` (−7..7), `mode` (major|minor). Unique per composition, sorted circle-of-fifths.
  - `composition_versions`: `key_id`, `number` (per key), `label`, `time_num`/`time_den`, `time_symbol` (none|common|cut), `tempo_bpm`, `tempo_text`, `pickup_ticks`, `instrument` (GM program), `score` (jsonb; phase 2 swaps `:map` for an embedded `Score`, no migration needed).
  - The version's key and time signature are *starting* values; changes partway through live in the score.
- **Changing key in the editor** transposes the notes after the user confirms, and saves as a new version under the target key (`save_in_key/4` creates the key if it's missing).
- **Delete rules:** deleting a key's only version removes the key. The composition's last version and last key can't be deleted.
- **Import resolution:** the key comes from the file's key signature.
  - `:new` returns `{:error, :name_taken}` on a collision.
  - `:replace` resets only that key's versions to v1.
  - `:new_version` adds the next version under that key, creating it if needed.
- **The structured score is canonical.** MIDI is generated on download.
  - The writer also embeds the score JSON in a **sequencer-specific meta event, FF 7F with manufacturer ID 0x7D**. The ID is reserved for non-commercial use, so our own files round-trip losslessly.
  - On import the blob is validated through changesets, and quantized MIDI conversion is the fallback.
- **API:**
  - `list_compositions`, `get_composition!`, `get_composition_by_name`, `get_version!(scope, id)`, `get_latest_version!(scope, key_id)`;
  - `create_composition(scope, comp, key, version)`, `update_composition`, `delete_composition`, `delete_key`, `delete_version`;
  - `save_version`, `save_new_version(scope, key, attrs)`, `save_in_key`, `save_as_new_composition`;
  - `import_score(scope, name, %{composition:, key:, version:}, resolution)`;
  - `Repo.transact` with a composition row lock wraps multi-step saves.

### Music domain (pure): `lib/draw_music/music/`
- **`Score`:** key (sf −7..7, mode), time_sig, tempo, ppq 960, `measures: [Measure{id, events}]`.
  - **Note:** id, staff, offset, value, dots, step, accidental, tie_to, chord_name.
  - **Rest:** staff, offset, value, dots.
  - A list of measures makes inserting and deleting bars a splice; ties reference ids, so they survive.
- **`Pitch`:** staff step ↔ letter/octave ↔ MIDI number, using the key signature and in-bar accidentals. Frequency is 440·2^((m−69)/12). Import spelling follows the key.
- **`Duration`:** note value + dots ↔ ticks; splits any length into tied note values.
- **`Beaming`, `Stems`, `Chords`:** the rules above. The chord catalog has maj, min, dim, aug, 7, maj7, m7, m7♭5, sus2, sus4, add9, plus diatonic triads I–vii°.
- **`Editing`:** pure Score → Score operations.
  - place, remove, move, dot, accidental, tie and untie;
  - insert, append and delete measures;
  - copy, paste, transpose by diatonic step, shift by beat.
  - A note that overfills its bar returns `{:error, :measure_full}`; notes pushed across a bar line are split into ties.
- **`Playback`:** builds a list of `%{id, start_s, dur_s, freq}` from a start tick or a range.

### MIDI: `lib/draw_music/midi/` (SUPERSEDED: use `ex_midi` for file encoding and decoding; keep only the score ↔ events mapping)
- **`VLQ`:** variable-length numbers.
- **`Writer`:** Format 1, 960 ticks per quarter. Track 0 holds name, tempo, time signature, key signature and the FF 7F blob; tracks 1 and 2 are treble and bass, each ending with FF 2F 00.
- **`Reader`:** formats 0 and 1, running status, velocity-0 note-on counts as note-off.
- **`ScoreCodec`:** quantizes to 64ths, assigns staff by track or by pitch, fills gaps with rests, and ties notes across bars.

### Web
**Build the UI from function components wherever possible** (user requirement):
- The palette (notes and rests), the transport, the chord catalog, the save menu, the import-collision dialog and the composition list rows are all components.
- LiveView templates mostly compose components.
- **Routes** (authenticated `live_session`):
  - `/compositions` (LibraryLive: list, versions, upload with collision dialog);
  - `/compositions/new`;
  - `/compositions/:id/v/:n` (EditorLive).
  - `ExportController` serves `.mid` and `.svg`.
- **`ScoreComponents`:** grand staff, systems, measures, clef, key signature, time signature, notes, chords, rests, beams, ties, ledger lines, grid. Stable DOM ids `note-<id>`.
- **`PaletteComponents`:** note values, rests, dot, accidentals, tie, chord catalog, mode toggle, transport, zoom, tempo.
- **`ScoreEditor` hook:** an overlay with `phx-update="ignore"`. It handles the hover ghost note with tones, clicks to place, tie gestures, rubber-band selection, keyboard shortcuts and play-mode clicks, pushing committed edits to the server.
- **Audio:**
  - Hover tones use a Web Audio `OscillatorNode`.
  - Playback uses **Tone.js** (`npm i tone --prefix assets`): a Transport plus a Sampler with piano samples vendored in `priv/static/samples`, falling back to a PolySynth.
  - The server sends playback events with `push_event`, and the hook highlights each note while it sounds.
  - There's no suitable Elixir audio library, and streaming tones from the server adds latency.
- **Fonts:** `Bravura.woff2` lives in `priv/static/fonts` with `@font-face` in `app.css`.
- **Score color scheme** (decided 2026-10-21): traditional (black notation on white paper) or dark (white notation on black).
  - It follows the app's existing System/Light/Dark header toggle (`Layouts.theme_toggle`, remembered per browser). There's no separate score switch.
  - `ScoreComponents` draw with CSS custom properties (`--score-ink`, `--score-paper`, plus the selection, hover-ghost and playback-highlight colors) set per `[data-theme]` in `app.css`. No colors are hard-coded in the SVG, so a switch needs no re-render.
  - Dark mode keeps the same contrast for selection, ghost-note and playback highlights.
  - **Dark-mode ink color is user-selectable** (decided 2026-10-21). It applies to notes, rests, staff lines, clefs, signatures, beams and ties; traditional mode is always black.
    - Picked from a few preset swatches (white (default), cream, amber, light green, light blue, light pink) or any custom color from a color picker.
    - Colors without enough contrast on black are refused with a message (WCAG contrast ratio of at least 7:1 against `#000`). The check runs in the changeset, so it holds for every way the color gets set.
    - Saved on the user account: a `score_ink_dark` field on `users` (a `#rrggbb` string, nil = white), so it follows the user to any device. It's set through a changeset on `User` with format and contrast checks, and changed from a "Score colors" section on the settings page and a swatch control in the editor palette.
    - The layout sets `--score-ink` inline from `@current_scope.user`, inside the dark theme only.
- **SVG export:** renders the score in print mode with Bravura embedded as base64 (about 250 KB). Exports are **always traditional** (black on white), whatever the screen shows.

## Environment: mise
- Add a project `mise.toml` pinning `erlang = "29.1.2"`, `elixir = "1.20.4-otp-29"` and `node = "23.8.0"` (needed for npm/Tone.js).
- Tasks: `setup`, `server`, `test`, `precommit`. No secrets in `[env]`.

## Version control: Jujutsu (jj 0.46)
- `jj git init --colocate` on the existing git repo (it's on `master` with no commits; `main` is the stated main branch).
- Set the jj user name and email if they're unset.
- Change 1: the Phoenix scaffold + `mise.toml`. Then one described change per phase, started with `jj new` and described with `jj describe -m`, each ending with the Co-Authored-By trailer.
- Keep the trunk bookmark **`master`** on the latest finished phase.
- No remote or push unless asked.

## Phases
1. mise + jj setup; auth; Library schemas, context and tests.
2. Music domain + MIDI, with tests.
3. Read-only rendering + SVG export.
4. Editing.
5. Audio + play mode.
6. Library upload/import dialog + `.mid` download.

## Verification
- **`mix test`:**
  - VLQ against the spec table; the writer matches the spec's example bytes; MIDI round trips.
  - Editing rules: ties across bars, measure_full, range limits, transpose and shift.
  - Beaming and stems; Library collision paths.
  - LiveView tests via `render_hook` and `file_input`.
- **Manual:**
  - Paint notes and listen.
  - Open a downloaded `.mid` in MuseScore.
  - Re-upload it and try all four collision choices.
  - Open the SVG export without Bravura installed.
  - Switch Light/Dark while editing: the score flips between black-on-white and white-on-black without reloading, and the SVG export stays black on white.
  - Pick an amber ink in dark mode: the score redraws in amber, the color survives logging in from another browser, and a near-black custom color is refused.
- `mix precommit` is clean.
