# Phase 5: Audio + Play mode

## Context
Phases 1–4 store, draw and edit scores. The demo slice (2026-10-22) added
a Play/Stop button (and Space). It plays from the selection, or from the
start, through a built-in Tone.js `PolySynth`, and highlights each note
as it sounds. Placement tones are a short Tone.js `Synth` beep.

Phase 5 finishes audio and playback:
- sampled instruments, self-hosted;
- an instrument picker;
- a Play mode, so listening can't edit the score by accident;
- Pause, Rewind, range playback and Loop;
- a Credits page for the sample and font licenses.

**Before Phase 5 code:** finish the paused code review
(`plans/code-review-continuation.md`). Phase 5 changes the files with
the most open review findings: `editor_live.ex`, the palette, the
settings form and the layouts. The review stays in its own change on the
`Phase-5` branch.

## Decisions (2026-10-23)
- **Sampled instruments** use **smplr** (npm, MIT, 1.1.0).
  - GM program 0 (Acoustic Grand Piano) is the **Splendid Grand Piano**
    (Akai, public domain).
  - Every other program is its **MusyngKite** soundfont (gleitz
    `midi-js-soundfonts`, CC BY-SA 3.0).
- **Samples are self-hosted** and never loaded from a CDN at run time.
- **Default set:** the Splendid Grand Piano plus 12 MusyngKite
  instruments: electric_piano_1, harpsichord, church_organ,
  acoustic_guitar_nylon, violin, cello, flute, clarinet, trumpet,
  choir_aahs, marimba, and acoustic_grand_piano. The last is a lighter
  fallback for the piano: if the Splendid samples are missing, program 0
  uses it.
  - Measured: about 31 MB of MusyngKite, plus about 25 MB per piano
    format (ogg, and m4a for Safari), so about 80 MB in all.
- **More instruments** come from `mix samples.fetch <name>…`. Fetching on
  demand by an admin is noted in the main plan for later, and isn't part
  of Phase 5.
- **Placement tones stay a beep** until parts arrive (Phase 9). The
  sampled instrument is for playback only.
- **The instrument picker** goes in the score settings dialog. It sets
  `version.instrument`, which is an ordinary setting that saves in place
  until Phase 9 moves it into parts.
- **Play mode:** an Edit / Play toggle (shortcut **P**). In Play mode
  nothing can change the score.
- **Play controls work in both modes:**
  - Play / Pause (Space);
  - Rewind (Home);
  - Loop (L);
  - Escape stops while playing.
- **The browser owns the timing.** The server sends one span of timed
  events per Play. Pause, resume, rewind and loop are handled in the
  browser without another round trip.

## Revision after the user's review (2026-10-23)
These replace the decisions above wherever they differ.

- **Edit and Play are fully distinct, with one palette each.** The toolbar shows:
  - **in both modes:** the Edit/Play switch, help (?) and Save;
  - **in Edit mode only:** the edit palette (durations, rest, dot, accidentals, tie, chords, Insert, score settings, undo, redo);
  - **in Play mode only:** the play controls (Rewind, Play/Pause, Loop, the playback instrument, "Use for this version").
- **Keys follow the mode.**
  - Space, Home, L, and Esc-to-stop work only in Play mode.
  - The editing keys work only in Edit mode.
  - P and ? work in both.
  - The server ignores the play events in Edit mode, and the edit events (score settings included) in Play mode.
- **Switching to Edit stops playback.**
- **Playback instrument** ("Hear as", in the play controls):
  - it is for listening only;
  - it starts as the version's instrument, and changes to it last through mode switches until the editor is reopened;
  - **Use for this version** (asks for confirmation, enabled only when the two differ) sets the version's instrument, which marks the version unsaved; Save stores it;
  - the score settings dialog still sets the version's instrument, and playback then follows that new instrument.
- **Chord preview while placing:**
  - the cursor shows the whole chord;
  - the hover tone sounds the whole chord together;
  - a label names it (e.g. Cm, B♭7; ii · Dm for a scale-degree chord).
- **Bug fixed:** the palette's value buttons and the menu's length buttons sent an empty `value` from the browser. LiveView replaces `phx-value-value` with the button's own `value`, so these buttons now carry a real `value` attribute.

## Samples: `DrawMusic.Samples`
- **The GM table:** 128 entries of `%Samples.Instrument{program, name,
  family, soundfont_name}`.
  - `name` is the display name ("Acoustic Guitar (nylon)").
  - `family` is one of the 16 GM families (Piano, Chromatic Percussion,
    Organ, Guitar, Bass, Strings, Ensemble, Brass, Reed, Pipe, Synth
    Lead, Synth Pad, Synth Effects, Ethnic, Percussive, Sound Effects).
  - `soundfont_name` is the MusyngKite file stem (`acoustic_guitar_nylon`).
  - Source: the GM 1 program list; the stems follow gleitz's
    `names.json`.
- **Functions:**
  - `instruments/0`;
  - `instrument!(program)`;
  - `families/0`, in GM order;
  - `default_set/0`;
  - `installed?(program)`;
  - `installed/0`, which reads the manifest;
  - `fetch(program_or_name, opts)`, which downloads with Req.
- **Sources** are fixed in the module, one base URL per set:
  - `https://gleitz.github.io/midi-js-soundfonts/MusyngKite/`
  - `https://smpldsnds.github.io/sfzinstruments-splendid-grand-piano/samples/`
  - Names are only ever looked up in the GM table.
- **Storage:** `config :draw_music, :samples_dir`, which defaults to
  `priv/samples` (git-ignored).
  - `<dir>/musyngkite/<stem>-mp3.js`
  - `<dir>/splendid-grand-piano/<sample>.{ogg,m4a}`, with the sample
    list taken from smplr's piano layer table and copied into the module.
  - `<dir>/manifest.json`, which lists the installed programs with their
    sizes and fetch dates.
  - The license files sit next to the samples: MusyngKite's CC BY-SA 3.0
    notice and the piano README's public-domain statement.
- **Fetching:**
  - files already present with the right size are skipped;
  - downloads go to a temp file, which is renamed into place when done;
  - a failed instrument doesn't stop the others;
  - the manifest is rewritten at the end;
  - the task prints a short line per instrument.
- **Serving:** a second `Plug.Static` in the endpoint, `at: "/samples"`,
  `from: samples_dir`, with long cache headers. It isn't part of
  `static_paths`, because those files are digested assets from
  `priv/static`.

### `mix samples.fetch`
- With no arguments it fetches `default_set/0`. With arguments, the names
  are GM display names, soundfont stems, or program numbers. An unknown
  name is an error that lists close matches.
- `--list` prints all 128 instruments and marks the installed ones.
- `mix setup` gains `samples.fetch`. It's left out of `mix test` and `mix
  precommit`, which never touch the network.

## Browser: instruments and playback
- **One AudioContext:** smplr is given Tone's raw context
  (`Tone.getContext().rawContext`), so the beep and the instruments share
  one clock and one unlock gesture.
- **Loading:**
  - the editor tells the hook the version's program, whether it's
    installed, and its sample URL (a `data-instrument` attribute on the
    hook element);
  - the hook starts loading as soon as it mounts and loads again when the
    instrument changes;
  - while it loads, the Play button reads "Loading <instrument>…" and
    still works, falling back to the synth.
- **Fallback:** if an instrument isn't installed or fails to load, playback
  uses the existing `PolySynth`, and a flash notice names the instrument.
- **Scheduling:**
  - each event is `instrument.start({note: midi, time: t0 + start,
    duration})`;
  - highlights run from a `requestAnimationFrame` loop that compares
    `ctx.currentTime` with the event times, replacing the
    `setTimeout`s.
- **Pause:**
  - records `elapsed = ctx.currentTime − t0`;
  - stops every voice and clears the highlights;
  - the play state becomes `paused`.
- **Resume:** reschedules the events whose `start + duration > elapsed`.
  An event already sounding restarts at the resume time with its
  remaining duration.
- **Rewind:** sets `elapsed = 0`. If it was playing, it carries on from
  the start point.
- **Loop:**
  - when on, reaching the end of the span reschedules it from 0;
  - when off, the end stops playback and sends `playback_ended`.
- **Stop** (Escape while playing, or an edit): clears everything, and the
  next Play asks the server for events again.
- **States**, reported to the server with a `playback_state` event, so the
  buttons render correctly:
  - `idle`
  - `loading`
  - `playing`
  - `paused`

## Server: `EditorLive`
- **New assigns:**
  - `mode: :edit | :play`;
  - `playback: :idle | :loading | :playing | :paused`, which replaces
    `playing?`;
  - `loop?: boolean`.
- **Events:**
  - `toggle_mode`, which disarms any armed value and keeps the selection.
  - `play`, which depends on the playback state:
    - **idle:** computes the span (below) and pushes `play` with
      `%PlaybackPayload{events, loop?}`;
    - **playing:** pushes `pause`;
    - **paused:** pushes `resume`.
  - `rewind`, which pushes `rewind`.
  - `toggle_loop`, which flips `loop?` and pushes `loop` with the new
    value.
  - `stop`, which pushes `stop`.
  - `audition` (`%{"id" => id}`, Play mode only), which pushes
    `audition` with the pitches of every note on that staff sounding at
    the note's offset (its chord). It also makes the note the
    selection, and so the start point.
  - `playback_state` and `playback_ended`, sent by the hook.
- **The span:**
  - several events selected: from the earliest start to the latest end
    (`Playback.events(score, ctx, from:, to:)`);
  - a single event selected: from its start to the end;
  - nothing selected: the whole score.
- **Play-mode guard:**
  - every editing event (`place`, `move`, `delete`, `cut`, `paste`,
    `undo`, `redo`, the tie events, `open_menu`, the palette arm and
    toggle events, `toggle_insert`) is ignored in `:play`, with no
    change and no flash;
  - one function-head clause per handler group, matched on `mode:
    :play`, rather than an `if` in each.
- **Any score change stops playback** (`stop` is pushed), because the
  events the browser holds are out of date. Changing the instrument in
  settings reloads it.
- **`Playback`:** adds nothing beyond a `chord_at(score, ctx, id)`
  helper for `audition`. It returns `[PlaybackEvent.t()]` timed from 0.

## Hook changes (`assets/js/score_editor/`)
- A new `audio.js` module holds the context, instrument loading, the
  synth fallback, scheduling, pause, resume, rewind, loop and the
  highlight loop. `index.js` keeps the input handling.
- The hook reads `data-mode`:
  - in `play`, a click on a note sends `audition`, a drag runs the
    rubber band (`select_range`, as in Edit mode), and the ghost note,
    placement, tie gestures and the edit keys are inactive;
  - the score gets a `.play-mode` class for the cursor.
- **New keys:**
  - **P**: `toggle_mode`;
  - **Home**: `rewind`;
  - **L**: `toggle_loop`;
  - **Escape** while playing: `stop`, which takes priority over disarm or
    clear selection.

## Components
- **`PaletteComponents`:**
  - a mode toggle (Edit / Play, `aria-pressed`, ids `palette-mode-edit`
    and `palette-mode-play`);
  - the transport: Play/Pause (`palette-play`), Rewind
    (`palette-rewind`), Loop (`palette-loop`, `aria-pressed`);
  - the Play button's label follows the playback state: Play, Pause,
    Resume, or Loading <instrument>…;
  - in Play mode the note, rest, accidental, tie, chord and insert
    groups render disabled.
- **`LibraryComponents.score_settings_fields/1`** gains the instrument
  select (`settings-instrument`):
  - options are grouped by family (`<optgroup>`);
  - uninstalled ones are labelled "(not installed)";
  - the editor settings dialog and the new-composition form both use it.
- **`EditorSettings`** carries `instrument` through `form_attrs/1` and
  validation (0..127).
- **`Layouts.app`** gains a footer with a link to Credits (`footer-credits`).

## Credits page
- `/credits`: `CreditsLive`, a static page in the existing
  `live_session :current_user`, so it works with or without a login.
- **Sections:** the Bravura font, SMuFL glyph names, Tone.js, smplr,
  MusyngKite soundfonts, the Splendid Grand Piano and ex_midi. Each gives
  the copyright holder, license name with a link, source link, and what
  we use it for.
- MusyngKite: "Musyng Kite soundfont, converted for the web by Benjamin
  Gleitzman (midi-js-soundfonts), licensed CC BY-SA 3.0". It links to
  the license (`https://creativecommons.org/licenses/by-sa/3.0/`) and to
  the source repository, since the license requires credit and a link.
- `THIRD_PARTY_NOTICES.md` gains the same entries. The page's content
  is a list of `%Credit{}` structs in the module.

## Cheat-sheet (added 2026-10-23)
There isn't one yet. Phase 5 creates it, covering everything built so far
(the Phase 4 editing interactions as well as Phase 5's). Every later phase
updates it as part of finishing each feature.

- **Where:**
  - a `/help` page (`HelpLive`, in `live_session :current_user`) linked
    from the footer;
  - the same content in an editor dialog opened with **?** or a toolbar
    button (`palette-help`), so it can be checked mid-edit without losing
    work;
  - Esc closes the dialog.
- **One source:**
  - `DrawMusicWeb.Shortcuts` holds a list of `%Shortcut{group, keys,
    mouse, modes, action}` structs;
  - groups: Placing, Selecting and moving, Ties and chords, Measures,
    Editing, Saving, Playback, Modes;
  - `modes` is `[:edit]`, `[:play]` or both;
  - the page and the dialog both render from it, and the dialog shows
    the current mode's entries first.
- **Diagrams:**
  - small inline SVGs drawn with the score's own components and Bravura,
    so they match what's on screen;
  - Phase 4 diagrams: the ghost note snapping to a line or space;
    Shift/Ctrl adding ♯/♭; the drag from one note to the next that makes
    a tie; a rubber-band selection across both staves; Insert mode
    pushing later notes on one staff right;
  - Phase 5 diagrams: Play mode's speaker cursor and audition click;
    range playback over a selected span; Loop repeating the span.
  - Diagrams go in a `HelpComponents` module, as function components.
- **Keeping it current:**
  - a test asserts that every key the hook handles has a `%Shortcut{}`
    entry;
  - the list of handled keys is exported from `assets/js/score_editor/`
    as `KEYS` and mirrored in `Shortcuts.handled_keys/0`, and the test
    compares the two;
  - each later phase's spec has a "Cheat-sheet" item.

## Testing (functionality only)
- **`Samples`:**
  - the table has 128 programs with unique stems, and every family is
    present;
  - `default_set` programs are all in the table;
  - name, stem and number lookups work, and an unknown name gives
    suggestions;
  - the manifest round-trips, and `installed?` reads it, using a temp
    `samples_dir`;
  - `fetch` against a stubbed source (`Req.Test`) skips a complete file,
    replaces a short one, and keeps going after one instrument fails.
- **`Playback.chord_at`:** the notes of a chord on one staff, not the
  other staff, with the key's accidentals applied.
- **`EditorLive`:**
  - `toggle_mode` disarms and keeps the selection;
  - each editing event in Play mode leaves the score unchanged;
  - `audition` pushes the chord's pitches and selects the note;
  - `play` pushes the span for a range, a single selection, and no
    selection, then `pause` and `resume` on the next presses;
  - an edit while paused pushes `stop`;
  - `toggle_loop` pushes `loop`.
- **Settings:** an instrument outside 0..127 is refused, and the saved
  instrument reaches the version.
- **Credits:** the page renders for a signed-out visitor and has the
  footer link.
- **Cheat-sheet:**
  - `/help` renders signed out;
  - **?** opens the editor dialog (`#help-dialog`) and Esc closes it;
  - every `Shortcuts.handled_keys/0` key has an entry;
  - Play-mode entries come first while in Play mode.

## Verification
- `mix test` passes and `mix precommit` is clean.
- **Manual (browser):**
  - after `mix samples.fetch`, the piano plays sampled, not synth;
  - pick Flute in settings and save: playback is a flute, and the choice
    survives a reload;
  - pick an instrument that isn't installed: it's listed as "(not
    installed)", playback uses the synth, and a notice says so;
  - Pause mid-phrase, then Resume: it continues from the same note, and
    the highlights match the sound;
  - select bars 2–3 and play: only that range sounds; with Loop on it
    repeats until stopped;
  - Home while playing restarts from the start point;
  - Play mode: clicking a note sounds its chord; dragging, placing, the
    arrows and Delete change nothing; P returns to Edit;
  - Safari: the piano loads the m4a samples;
  - the Credits page is reachable from the footer when signed out;
  - the cheat-sheet lists every key and mouse action that works, its
    diagrams match the score in both light and dark themes, and **?**
    opens it from the editor.
