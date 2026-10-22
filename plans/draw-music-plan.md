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
- **Key and instrumentation set a version apart** (added 2026-10-23; phase 9):
  - What makes a version distinct is its key *and* its parts, meaning the instruments it's scored for. "D major for flute and piano" is a different version from "D major for piano" and from "C major for flute and piano".
  - **Terminology:** this plan calls an instrument line a **part**. In the code, `Note.voice` (1–4) already means an independent rhythmic line within one staff, which is a different thing, so the two names stay separate.
  - Most versions have one part. Several are allowed, e.g. **flute and piano**: a flute staff above the piano's braced grand staff.
    - The brace joins one instrument's staves (piano treble and bass).
    - A system bracket and the system's left-hand barline join the different parts.
    - Barlines run through each part's staves but break between parts.
    - Part names appear at the start of each system.
  - Each part has a name, a GM instrument and a staff layout: **grand** (braced treble + bass), **treble**, **bass**, or **treble 8vb** (guitar, which sounds an octave below where it's written).
  - Parts are listed in score order, top to bottom (e.g. woodwinds above piano). The arrangement name ("for flute and piano") is built from the part names.
  - **Generation:** a version's key and parts are fixed once saved.
    - Changing either in the editor (transposing, or adding, removing or re-instrumenting a part) can't overwrite the version.
    - The save offers only **Save as new version** into the matching key + arrangement, creating it if missing, or **Save as new composition**. This extends today's "changing key saves under the target key".
    - Changing a part's name, or anything else that isn't part of the identity (tempo, notes, time signature), saves normally.
- **Editor saves:** **Save** (overwrite current version) · **Save as new version** · **Save as new composition** (name prompt + collision check).
- **Import:**
  - The name comes from the MIDI track name (FF 03), falling back to the filename, and the user can edit it.
  - On a name collision the user chooses: **Cancel** · **Replace** (delete all versions, store as v1) · **New version** · **New composition with a different name** (re-checked).
- **Rendering:** server-rendered SVG function components with **Bravura** (SMuFL) glyphs, on a **grid**: x = ticks (proportional spacing, zoomable), y = diatonic staff positions.
- **Score layout is a user preference** (decided 2026-10-22):
  - **Strip** (default): the whole song as one long, scrolling grand staff.
  - **Page:** measures wrapped into systems, like printed sheet music.
  - Both come from one layout engine, and editing works the same in both.
  - SVG export is always page layout.
  - Details are in `plans/phase-3-rendering.md`.
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
  - chord symbols (names) and guitar chord diagrams above the treble staff (see below; phase 10);
  - automatic beaming.
- **Chord symbols and guitar fingering** (added 2026-10-23; phase 10):
  - **Why:** a novice may not recognize a stack of notes as a chord. An explicit name such as `Cmaj7` or `G/B` above the staff says it directly, and a guitar diagram shows where to put the fingers.
  - **What's shown:** a chord lane above the treble staff, aligned to the symbol's offset in ticks. The layout reserves room for it above the highest note or ledger line in each system.
    - **Name:** the usual lead-sheet short form: the root letter and accidental, then a quality suffix, plus an optional slash bass (`C/E`).
      - A major chord is the root alone (`C#`); a minor chord adds `m` (`Cm`).
      - The rest of the catalog uses `dim`, `aug`, `7`, `maj7`, `m7`, `m7♭5`, `sus2`, `sus4`, `add9`.
      - Accidentals display as ♯/♭.
    - **Guitar diagram:** a fret grid above the name (standard tuning E A D G B E), with a dot per fretted string, a finger number 1–4 in the dot, `x` for muted strings, `o` for open ones, a barre line, and a base-fret number when it isn't the first fret. Drawn with SMuFL fretboard glyphs (U+E850–U+E85F) so the SVG export matches.
  - **Display setting** (per version, in score settings): **Off** · **Names** · **Names + guitar diagrams**.
    - The default is diagrams when any part is a GM guitar (programs 24–31), and names otherwise.
    - Names go above the system's top staff, and diagrams go above each guitar part's staff. Parts arrive first, in phase 9.
  - **Entering symbols:**
    - Placing a chord from the catalog also adds its symbol (on by default, a toggle in the chord menu).
    - **Name chord** on a selected stack infers the symbol from the notes (new `Chords.identify/1`, the inverse of `build/3`). Inversions become slash chords, and an unrecognized stack is refused with a message.
    - Typing a symbol (`F#m7b5`, `Bb/D`) on a beat places it; `ChordSymbol.parse/1` accepts ASCII `#`/`b` as well as ♯/♭.
    - Click a symbol to select it; Delete removes it, and it moves and copies with a selection.
  - **Fingerings** come from a voicing table, preferably an off-the-shelf data set (candidate: `@tombatossals/chords-db`, guitar JSON; check its license first) converted into a compile-time Elixir table. The first voicing is the default, and the user can step through the alternatives on a selected diagram. A chord with no voicing shows only its name.
  - **Editing rules:** transposing a selection respells the symbols (`Pitch.transpose/5`) and looks the diagrams up again. Symbols aren't played back, since the notes already sound.
  - **MIDI:** exported as text meta events (`FF 01`, `chord:<symbol>[|<frets>]`) and read back on import. Other programs ignore them.
  - **Out of scope for now:** per-note fingering numbers (left-hand 1–4, right-hand p i m a) and tablature staves.
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
  - **Measured sizes (2026-10-23):**
    - MusyngKite instruments are about 1.6–3.0 MB each as `-mp3.js`, so the 12 cost about 31 MB.
    - The Splendid Grand Piano has about 300 samples (4 velocity layers) at about 75–100 KB each per format. That's about 25 MB for ogg and about the same again for m4a, which Safari needs.
    - The default set is about 80 MB on disk.
  - `mix samples.fetch <gm-name>…` adds individual instruments later (decided 2026-10-23).
  - **For consideration (not scheduled): server fetch on demand, for admins.** An admin picking a "not installed" instrument could have the server download it, instead of someone running the mix task. The work this needs:
    - **Roles:**
      - a `role` column on `users` (`user` | `admin`, default `user`) plus a migration;
      - `Scope` carries the role, and a small policy module, `DrawMusic.Accounts.Policy.allowed?(scope, :fetch_samples)`, holds the rules so templates and handlers ask it instead of checking roles themselves;
      - a way to make the first admin: `mix users.promote <email>`, or an `ADMIN_EMAILS` runtime config for the release;
      - no role-management UI at first.
    - **One fetch module** (`DrawMusic.Samples`) used by both the mix task and the server:
      - instrument names come only from the GM table and sources from an allowlist, never a URL from the client;
      - it checks size and type before writing, and copies the license file next to the samples;
      - a manifest lists the installed instruments.
    - **Background job:** a supervised task, one per instrument at a time (deduplicated through a `Registry`), with progress sent over PubSub so the picker updates live. If jobs need to survive restarts, use Oban (off-the-shelf) rather than a hand-rolled queue.
    - **Writable storage:** a release's `priv/static` is read-only and replaced on every deploy. Fetched samples need a configured directory outside the release (`:samples_dir`, e.g. a mounted volume) served at `/samples` by its own `Plug.Static`. This affects Phase 7 whether or not on-demand fetch is built.
    - **UI:**
      - admins see "Download" beside a not-installed instrument, then a progress bar;
      - everyone else sees "Not installed: ask an admin" and plays the synth in its place.
    - **Limits:** a disk quota and a cap on concurrent fetches. Fetches are logged with the admin's id.
    - **Tests:** the policy (admin yes, user no), the handlers refusing non-admins, the duplicate-fetch guard, and the manifest update. Network downloads stay behind a stubbed source.
- **Not used:** midiex (live MIDI ports, maybe later for keyboard input), midi_synth / TuningFork (they make sound on the server, which users can't hear), @tonejs/midi (files are handled on the server).
- **Attribution:**
  - A Credits page (footer link) and `THIRD_PARTY_NOTICES.md`.
  - MusyngKite needs credit plus a license link.
  - Bravura ships with `OFL.txt`.
  - Keep MIT notices.

## Architecture

### Persistence: `DrawMusic.Library`
- `mix phx.gen.auth Accounts User users --live` (this adds `Scope`; every context function takes it).
- **Hierarchy:** Composition → Key → Version (built). Phase 9 adds a level: Composition → Key → **Arrangement** → Version.
  - `composition_arrangements` (phase 9): `key_id`, `parts` (jsonb list: name, instrument, staves).
    - Unique per key on its instrumentation signature, the ordered list of instrument + staff layout. Part names are left out of the signature.
    - Versions get `arrangement_id`, and `number` becomes per arrangement.
    - `version.instrument` moves into the parts.
    - A migration gives each existing version a one-part arrangement built from its `instrument` with a grand staff, so current numbers carry over.
    - Delete rules extend the same way: deleting the last version removes the arrangement, then the key, but never the composition's last one.
    - `save_in_key/4` becomes `save_in_arrangement(scope, composition, key_attrs, parts, version_attrs)`.
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
  - **Part** (phase 9): id, name, instrument, staves. `Score.parts` mirrors the arrangement's parts and defaults to one grand-staff part.
  - **Note:** id, staff, voice, offset, value, dots, step, alter, tie_to; phase 9 adds `part_id`. A staff is then identified by the pair (part, staff).
  - **Rest:** staff, offset, value, dots.
  - **ChordSymbol** (phase 10): id, offset, root step and alter, quality, optional bass step and alter, optional `frets` (six entries, each muted, open or fret plus finger). It goes in `Measure.chord_symbols`, an embedded list with no migration needed. It replaces the never-built `Note.chord_name`.
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
   - **Demo slice done (2026-10-22):** a Play/Stop button (and Space) that plays from the selection or the start through a built-in Tone.js synth, highlighting notes as they sound. Still to do: sampled instruments, the instrument picker, `mix samples.fetch` and the Credits page.
6. Library upload/import dialog + `.mid` download.
   - **`.mid` download done in the demo slice.** Still to do: upload/import and the collision dialog.
7. **Deployment** (added 2026-10-22; not started):
   - `mix phx.gen.release` (with a Dockerfile);
   - runtime config for `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PHX_SERVER`, and release migrations;
   - fetching the audio samples at build time (`mix samples.fetch`);
   - a hosting target, chosen at the time, so testers can reach the app.
8. **Live MIDI keyboard input** (added 2026-10-22; not started):
   - Play notes from a connected MIDI keyboard into the score: a key press places the armed value at the cursor, chords included.
   - Browser Web MIDI API in the `ScoreEditor` hook (no server-side MIDI).
   - It sends the existing `place` event, so it uses the same editing rules.
   - Browser support varies (Chromium-based browsers; Firefox asks permission; Safari has none), so it's an optional extra.
9. **Parts and arrangements** (added 2026-10-23; not started; design under Decisions). It comes before chord symbols because it changes the database schema, and the guitar diagrams attach to guitar parts:
   - Library: the `composition_arrangements` table plus a data migration; versions numbered per arrangement; `save_in_arrangement`; delete rules; the composition list grouped as key, then arrangement, then versions.
   - Domain: `Part`, `Note.part_id`, and `Editing` that works per part, including range limits per part.
   - Rendering: systems stacked from the parts, with the bracket, braces, part names, barlines broken between parts, and the 8vb treble clef.
   - Editor:
     - a parts dialog to add, remove, reorder and re-instrument parts, which forces a new version;
     - placing notes on whichever part's staff is under the pointer;
     - the save menu following the generation rule.
   - Playback: one smplr instrument per part.
   - MIDI: a format 1 file with one track per part, each with its own program change and track name. On import each track becomes a part, and two tracks with the same program on treble and bass ranges merge into one grand-staff part.
10. **Chord symbols and guitar fingering** (added 2026-10-23; not started; design under Decisions):
    - domain: `ChordSymbol` (struct, parse, format), `Chords.identify/1`, the voicing table, and `Editing` operations to add, remove, move and transpose symbols;
    - rendering: the chord lane and fret diagrams in `ScoreComponents` and the SVG export, plus the layout's headroom;
    - editor: catalog auto-symbol toggle, Name chord, typed entry, voicing stepper, and the display setting;
    - MIDI text-event export and import.

## Verification
- **`mix test`:**
  - VLQ against the spec table; the writer matches the spec's example bytes; MIDI round trips.
  - Editing rules: ties across bars, measure_full, range limits, transpose and shift.
  - Beaming and stems; Library collision paths.
  - Chord symbols:
    - `identify` round-trips `build` for every quality and root, and turns inversions into slash chords;
    - `parse`/`format` round-trip;
    - transposing respells (C → D♭ keeps flats in flat keys);
    - MIDI text events round-trip.
  - Arrangements:
    - Changing the key or the parts on a saved version can't overwrite it; it saves as a new version under the matching arrangement, created on demand.
    - Renaming a part saves in place.
    - The same instrumentation under a different part name is the same arrangement.
    - The migration keeps existing version numbers.
    - A flute + piano MIDI file round-trips with two parts.
  - LiveView tests via `render_hook` and `file_input`.
- **Manual:**
  - Paint notes and listen.
  - Open a downloaded `.mid` in MuseScore.
  - Re-upload it and try all four collision choices.
  - Open the SVG export without Bravura installed.
  - Switch Light/Dark while editing: the score flips between black-on-white and white-on-black without reloading, and the SVG export stays black on white.
  - Pick an amber ink in dark mode: the score redraws in amber, the color survives logging in from another browser, and a near-black custom color is refused.
- `mix precommit` is clean.
