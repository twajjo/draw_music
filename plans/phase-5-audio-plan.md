# Phase 5: Audio + Play mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sampled, self-hosted instruments with a picker. A Play mode, plus
Pause, Rewind, range playback and Loop. A Credits page and an in-app
cheat-sheet.

**Architecture:**
- `DrawMusic.Samples` owns the GM table, the sample storage and manifest,
  and downloading (Req). `mix samples.fetch` drives it.
- The endpoint serves `samples_dir` at `/samples`.
- `EditorLive` owns the mode, the playback state and the play span, and
  it sends one batch of timed events per Play.
- A new hook module, `assets/js/score_editor/audio.js`, plays them through
  smplr and handles pause, resume, rewind and loop locally.

**Tech Stack:** Elixir/Phoenix 1.8, LiveView 1.2, Req (+ `Req.Test`),
smplr 1.1.0 (npm, MIT), Tone.js 15 (already present), jj (colocated) and
mise.

**Spec:** `plans/phase-5-audio.md`

## Global Constraints
- **Branch:** all work goes on jj bookmark `Phase-5`, on top of `master`
  (`175792fd`).
  - Each task ends with `jj commit -m "<msg>"` and no `Co-Authored-By` or
    other Claude attribution.
  - Move the bookmark at the end of each task: `jj bookmark set Phase-5
    -r @-`.
  - Never push without the user saying so.
- **Edits:** only through the Write and Edit tools, in manual mode. Never
  through shell redirection or sed.
- **Elixir style:**
  - a pipeline with two or more `|>` goes one stage per line;
  - no `, do:` form for a body that wraps;
  - function heads or `case` rather than `if`/`cond` where a match fits;
  - `with … else` only when the `else` doesn't depend on which step
    failed; otherwise use tagged errors from each step, `case`, or
    function clauses;
  - `@spec` on every public function, function components included;
  - fixed-shape records are structs with `@type t`.
- **Tests are functionality only:** our validations and logic, never Ecto
  round-trips or defaults. No test touches the network: `Samples` uses a
  `Req.Test` stub.
- **UI** is built from function components, and LiveView templates live in
  `render/1`.
- **DOM ids, exactly as given:**
  - `palette-mode-edit`, `palette-mode-play`
  - `palette-play`, `palette-rewind`, `palette-loop`, `palette-help`
  - `settings-instrument`
  - `footer-credits`, `footer-help`
  - `help-dialog`
- **Sample URLs:**
  - `https://gleitz.github.io/midi-js-soundfonts/MusyngKite/<stem>-mp3.js`
  - `https://smpldsnds.github.io/sfzinstruments-splendid-grand-piano/samples/<name>.{ogg,m4a}`
- **The default set:** the Splendid Grand Piano plus these MusyngKite
  stems: `acoustic_grand_piano electric_piano_1 harpsichord church_organ
  acoustic_guitar_nylon violin cello flute clarinet trumpet choir_aahs
  marimba`.
- **Keys:**
  - **P**: toggle mode;
  - **Space**: play, pause or resume;
  - **Home**: rewind;
  - **L**: loop;
  - **Esc** while playing: stop;
  - **?**: the help dialog.
- **Cheat-sheet:** every feature task that adds a key or mouse action adds
  its `%Shortcut{}` entry in Task 8. Later phases add theirs as they land.
- `mix precommit` is clean at the end of every task.

## Review Focus
1. **A missing `samples_dir`, an absent manifest or a corrupt
   `manifest.json`:** nothing counts as installed, and nothing crashes.
   The picker shows everything "(not installed)" and playback uses the
   synth. (Task 2 test.)
2. **An interrupted download:** the partial file is never treated as
   installed. The temp file is removed, and the manifest has no entry for
   that instrument. (Task 2 test.)
3. **Play with nothing that sounds** (an empty score, or only rests
   selected): the state stays `:idle`, nothing is pushed, and a flash
   reads "Nothing to play here." (Task 5 test.)
4. **An edit while paused or playing:** `stop` is pushed, the state
   becomes `:idle`, and the next Play fetches fresh events. (Task 5 test.)
5. **Play mode:** Space, Home, L and Esc still work, and every editing
   event, including the ones sent straight from the hook (`place`,
   `move`, `tie`, `paste`), leaves the score and history unchanged.
   (Task 6 test.)

---

### Task 0: Finish the code review (before any Phase 5 code)

**Files:** as listed in `plans/code-review-continuation.md`.

- [ ] **Step 1:** Follow `plans/code-review-continuation.md` to the end:
  - extend `plans/review/equiv.exs` first;
  - then `editor_live.ex` and `editor_commands.ex`, then the rest of the
    table, then the other small files.
- [ ] **Step 2:** After each file, run `plans/review/run_equiv.sh`.
  Expected: `self-diff: 0  cur-diff: 0`.
- [ ] **Step 3:** Run `python3 -I plans/review/style_scan.py lib`.
  Expected: no lines, apart from the generated auth files and
  `core_components.ex`.
  - Then run `python3 -I plans/review/with_else.py lib` and judge each
    block it lists against the `with … else` rule.
  - Record each kept block in the ledger as `Ruling: kept with/else at
    <file:line> — else is uniform`.
- [ ] **Step 4:** Run `mix precommit`. Expected: clean, with all tests
  passing.
- [ ] **Step 5:** Wrap up:
  - delete `plans/review/` and `plans/code-review-continuation.md`;
  - delete the `code-review-paused` memory and its `MEMORY.md` line;
  - split the plan edits into their own change with `jj split
    plans/draw-music-plan.md plans/phase-5-audio.md
    plans/phase-5-audio-plan.md -m "Plans: phase 5 spec and plan, parts
    and chord symbols"`;
  - keep the review change's description;
  - `jj new`, then `jj bookmark set Phase-5 -r @-`.

### Task 1: The GM instrument table

**Files:**
- Create: `lib/draw_music/samples.ex`
- Create: `lib/draw_music/samples/instrument.ex`
- Test: `test/draw_music/samples_test.exs`

**Interfaces:**
- **Produces:**
  - `%Samples.Instrument{program: 0..127, name: String.t(), family: String.t(), stem: String.t()}`
  - `Samples.instruments() :: [Instrument.t()]`, in program order
  - `Samples.instrument!(0..127) :: Instrument.t()`
  - `Samples.families() :: [String.t()]`, the 16 families in GM order
  - `Samples.default_set() :: [Instrument.t()]`
  - `Samples.lookup(String.t()) :: {:ok, Instrument.t()} | {:error, {:unknown, [String.t()]}}`,
    which accepts a GM display name (case-insensitive), a stem, or a
    program number string.

- [ ] **Step 1: Write the failing tests**

```elixir
test "the GM table has 128 programs with unique stems and all 16 families" do
  instruments = Samples.instruments()
  assert Enum.map(instruments, & &1.program) == Enum.to_list(0..127)
  assert instruments |> Enum.map(& &1.stem) |> Enum.uniq() |> length() == 128
  assert instruments |> Enum.map(& &1.family) |> Enum.uniq() == Samples.families()
  assert length(Samples.families()) == 16
end

test "the default set is the 12 named stems" do
  assert Enum.map(Samples.default_set(), & &1.stem) ==
           ~w(acoustic_grand_piano electric_piano_1 harpsichord church_organ
              acoustic_guitar_nylon violin cello flute clarinet trumpet choir_aahs marimba)
end

test "lookup by name, stem or number; unknown names suggest close matches" do
  assert {:ok, %{program: 73}} = Samples.lookup("Flute")
  assert {:ok, %{program: 73}} = Samples.lookup("flute")
  assert {:ok, %{program: 24}} = Samples.lookup("acoustic_guitar_nylon")
  assert {:ok, %{program: 40}} = Samples.lookup("40")
  assert {:error, {:unknown, suggestions}} = Samples.lookup("flut")
  assert "flute" in suggestions
end
```

- [ ] **Step 2:** Run `mix test test/draw_music/samples_test.exs`.
  Expected: FAIL, because `Samples` is undefined.
- [ ] **Step 3: Implement.**
  - The table is a compile-time list built from gleitz `MusyngKite/names.json`
    (the stems) and the GM 1 program names. Families are 8 programs each,
    in program order.
  - Suggestions are stems with a `String.jaro_distance/2` of at least 0.8,
    best first, at most 5.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** `jj commit -m "Samples: GM instrument table"`, then
  `jj bookmark set Phase-5 -r @-`.

### Task 2: Storage, manifest, fetching, `mix samples.fetch`, and serving

**Files:**
- Create: `lib/draw_music/samples/manifest.ex`
- Create: `lib/draw_music/samples/splendid.ex`, the sample names copied
  from smplr's `LAYERS` table in `assets/node_modules/smplr/dist/index.mjs`
  (`src/splendid-grand-piano.ts`)
- Create: `lib/mix/tasks/samples.fetch.ex`
- Modify: `lib/draw_music/samples.ex`
- Modify: `config/config.exs` (`:samples_dir`, defaulting to
  `Path.expand("../priv/samples", __DIR__)`) and `config/test.exs` (a
  `Req.Test` plug: `config :draw_music, :samples_req, plug: {Req.Test, DrawMusic.Samples}`)
- Modify: `lib/draw_music_web/endpoint.ex`
- Modify: `mix.exs` (`setup` alias)
- Modify: `.gitignore` (`/priv/samples/`)
- Modify: `assets/package.json` (`npm i smplr@1.1.0 --prefix assets`)
- Test: `test/draw_music/samples_test.exs`,
  `test/mix/tasks/samples_fetch_test.exs`

**Interfaces:**
- **Consumes:** Task 1.
- **Produces:**
  - `%Samples.Manifest{soundfonts: %{String.t() => %{bytes: pos_integer(), fetched_at: DateTime.t()}}, splendid: %{bytes: pos_integer(), fetched_at: DateTime.t()} | nil}`
  - `Manifest.read(dir) :: Manifest.t()`, which never raises: a missing or
    corrupt file gives an empty manifest
  - `Manifest.write(Manifest.t(), dir) :: :ok`
  - `Samples.samples_dir() :: Path.t()`
  - `Samples.installed?(0..127) :: boolean()`
  - `Samples.splendid?() :: boolean()`
  - `Samples.fetch(Instrument.t() | :splendid, keyword()) :: {:ok, bytes} | {:error, term()}`
  - `Samples.fetch_many([Instrument.t() | :splendid], keyword()) :: [{Instrument.t() | :splendid, {:ok, bytes} | {:error, term()}}]`,
    which updates the manifest once at the end
  - opts: `dir:` (default `samples_dir/0`)
  - the paths `"<dir>/musyngkite/<stem>-mp3.js"` and
    `"<dir>/splendid-grand-piano/<name>.<ogg|m4a>"`

- [ ] **Step 1: Write the failing tests.** Use a temp dir per test
  (`@tag :tmp_dir`) and `Req.Test.stub(DrawMusic.Samples, fn conn -> … end)`.
  - `"an empty, missing or corrupt manifest means nothing is installed"`:
    - with no dir, `installed?(73) == false`;
    - after writing `"{not json"` to `manifest.json`, `Manifest.read/1`
      returns `%Manifest{soundfonts: %{}, splendid: nil}`.
  - `"fetch writes the file and records it; installed? reads the manifest"`:
    - stub a 10-byte body;
    - `fetch_many([flute], dir: dir)`;
    - the file exists with 10 bytes, and `installed?(73)` is true for that
      dir (`installed?/2` takes `dir:`).
  - `"a complete file is skipped; a short one is replaced"`:
    - run the fetch twice, and the stub counts requests (`Agent`): 1;
    - truncate the file to 3 bytes and fetch again: 2 requests and 10
      bytes.
  - `"a failed instrument leaves no file or manifest entry, and the others still land"`:
    - the stub returns 500 for `flute-mp3.js` and 200 otherwise;
    - fetch `[flute, cello]`: cello is installed, flute isn't;
    - no `*.tmp` is left in the dir.
  - `"the piano is installed if either the Splendid set or its soundfont is"`:
    write a manifest with `splendid` set; `installed?(0)` is true.
  - `samples_fetch_test.exs`, `"unknown name exits with suggestions"`:
    - `Mix.Tasks.Samples.Fetch.run(["flut"])` raises `Mix.Error`;
    - the message contains `flute`.
- [ ] **Step 2:** Run `mix test test/draw_music/samples_test.exs
  test/mix/tasks/samples_fetch_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Download with `Req.get(url, Application.get_env(:draw_music, :samples_req, []) ++ [into: File.stream!(tmp)])`.
  - Rename into place only on a 200 response; otherwise delete the temp
    file.
  - The Splendid set downloads both formats for every name in
    `Splendid.samples/0`. It counts as installed only when all of them
    land.
  - Copy the license text (CC BY-SA 3.0 for MusyngKite, the public-domain
    statement for the piano) as `LICENSE.txt` into each set's folder;
    the text is a module attribute.
  - The mix task:
    - `Mix.Task.run("app.config")`;
    - no arguments means `[:splendid | Samples.default_set()]`;
    - `--list` prints `program  name  [installed]`;
    - one line per instrument: `flute  2.8 MB  ok` or `flute  failed: <reason>`.
  - The endpoint, after the existing `Plug.Static`, gets
    `plug Plug.Static, at: "/samples", from: Application.compile_env(:draw_music, :samples_dir), cache_control_for_etags: "public, max-age=31536000"`.
    - The directory is fixed at compile time.
    - Phase 7 makes it a runtime setting for releases; add that to Phase
      7's list in `plans/draw-music-plan.md` in this task.
  - `mix.exs` `setup`: append `"samples.fetch"`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Run `mix samples.fetch` once by hand. Expected: 13
  lines of `ok`, about 80 MB under `priv/samples`, and
  `curl -sI localhost:4000/samples/musyngkite/flute-mp3.js` returns 200.
- [ ] **Step 6:** `jj commit -m "Samples: storage, manifest, fetch task, /samples"`,
  then move the bookmark.

### Task 3: The instrument picker and instrument source

**Files:**
- Create: `lib/draw_music_web/instrument_source.ex`
- Modify: `lib/draw_music_web/components/library_components.ex`
  (`score_settings_fields/1`)
- Modify: `lib/draw_music_web/editor_settings.ex` (`params/2`,
  `form_attrs/1`, `validate/1`)
- Modify: `lib/draw_music_web/live/editor_live.ex` (settings apply and
  save carry the instrument; `data-instrument` on `#score-editor`)
- Modify: `lib/draw_music_web/live/new_composition_live.ex`
- Test: `test/draw_music_web/live/editor_settings_test.exs`,
  `test/draw_music_web/instrument_source_test.exs`

**Interfaces:**
- **Consumes:** `Samples.instrument!/1`, `installed?/1`, `splendid?/0`,
  `families/0`.
- **Produces:**
  - `%DrawMusicWeb.InstrumentSource{program: 0..127, name: String.t(), kind: :splendid | :soundfont | :synth, url: String.t() | nil}`,
    which derives `Jason.Encoder`
  - `InstrumentSource.for_program(0..127) :: t()`. Program 0 gives
    `:splendid` (url `/samples/splendid-grand-piano/`) when
    `splendid?/0`. Any installed program gives `:soundfont` (url
    `/samples/musyngkite/<stem>-mp3.js`). Otherwise it's `:synth` with a
    nil url.
  - `EditorSettings.params(ctx, tempo_text, instrument)`, which gains a
    third argument and returns `"instrument"`.
  - `validate/1` returns `{:ok, key, fields}`, where `fields` includes
    `:instrument`.
  - `LibraryComponents.instrument_options() :: [{family, [{label, program}]}]`,
    with labels like `"Flute"` or `"Oboe (not installed)"`.
  - `EditorLive` assigns `:instrument` (0..127), seeded from the version
    and changed by settings.

- [ ] **Step 1: Write the failing tests.**
  - `instrument_source_test.exs`: with a temp `samples_dir` (via
    `Application.put_env` in `setup` and restored with `on_exit`, so the
    test is `async: false`):
    - nothing installed gives `:synth`;
    - a manifest with flute gives `for_program(73).kind == :soundfont`
      and `url == "/samples/musyngkite/flute-mp3.js"`;
    - with `splendid` set, `for_program(0).kind == :splendid`.
  - `editor_settings_test.exs`:
    - `"the settings form offers instruments grouped by family"`:
      `has_element?(view, "#settings-instrument optgroup[label='Pipe']")`
      and `has_element?(view, "#settings-instrument option[value='73']")`;
    - `"applying settings changes the instrument, and saving stores it"`:
      submit `instrument: "73"`, save, and `Library.get_version!(scope, id).instrument == 73`;
    - `"an instrument outside 0..127 is refused"`: submit `"128"`, then
      check that the error is on `#settings-instrument` and that
      `@instrument` is unchanged;
    - `"the hook is told the instrument"`:
      `#score-editor[data-instrument*='"program":73']` after applying 73.
- [ ] **Step 2:** Run `mix test test/draw_music_web/live/editor_settings_test.exs
  test/draw_music_web/instrument_source_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The `<optgroup>` labels are the GM family names from
    `Samples.families/0`, verbatim (flute is in "Pipe").
  - The `<.input type="select">` gets `options={LibraryComponents.instrument_options()}`.
    Phoenix's `options_for_select` accepts nested `{group, options}`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** `jj commit -m "Instrument picker in score settings"`,
  then move the bookmark.

### Task 4: Browser playback through smplr (`audio.js`)

**Files:**
- Create: `assets/js/score_editor/audio.js`
- Modify: `assets/js/score_editor/index.js`, which drops its
  `playEvents`/`stopPlayback`/`PolySynth` code and delegates to `Audio`

**Interfaces:**
- **Consumes:**
  - `data-instrument` (`InstrumentSource` JSON) on the hook element;
  - server pushes: `play {events, loop}`, `pause`, `resume`, `rewind`,
    `loop {on}`, `stop`, `audition {events}`.
- **Produces:**
  - pushes to the server: `playback_state {state: "loading"|"playing"|"paused"|"idle"}`
    and `playback_ended {}`;
  - in JS, `export class Audio { constructor(onState, onEnded, highlight); load(source); play(events, loop); pause(); resume(); rewind(); setLoop(on); stop(); audition(events) }`.

- [ ] **Step 1: Implement `Audio`.**
  - The context is `Tone.getContext().rawContext`.
  - `load(source)`:
    - `:splendid` → `new SplendidGrandPiano(ctx, {baseUrl: source.url})`;
    - `:soundfont` → `new Soundfont(ctx, {instrumentUrl: source.url})`;
    - `:synth` → the existing `Tone.PolySynth`;
    - then `await instrument.load`;
    - on a rejection, use the synth and call `onState("fallback")`.
  - `play`:
    - sets `t0 = ctx.currentTime + 0.05` and `elapsed = 0`;
    - schedules every event with `instrument.start({note: midi, time: t0 + start, duration})`;
    - starts a `requestAnimationFrame` loop that toggles `.playing` on
      `note-<id>` when `ctx.currentTime − t0` is inside `[start, start + duration)`.
  - `pause`: records `elapsed`, calls `instrument.stop()`, clears the
    highlights and cancels the animation frame.
  - `resume`:
    - `t0 = ctx.currentTime − elapsed`;
    - every event with `start + duration > elapsed` is scheduled at
      `max(start, elapsed)`, with its duration cut by the overlap.
  - `rewind`: `elapsed = 0`, then a resume when playing.
  - **At the end:** with loop on, `play` again with the same events;
    otherwise `stop`, then `onEnded`.
- [ ] **Step 2: Wire it into `index.js`.**
  - Construct `Audio` in `mounted`.
  - Call `load(JSON.parse(el.dataset.instrument))` in `mounted`, and in
    `updated` when the attribute changed.
  - Map the server events onto `Audio` methods.
  - Keep the placement beep (`this.synth`) as it is.
- [ ] **Step 3:** Run `mix assets.build`. Expected: builds with no
  errors.
- [ ] **Step 4: Manual check** (`mix phx.server`, after `mix samples.fetch`):
  - Play sounds a sampled piano;
  - with flute set, a flute;
  - with Oboe (not installed), the synth.
- [ ] **Step 5:** `jj commit -m "Playback through smplr instruments"`,
  then move the bookmark.

### Task 5: Transport — play state, span, pause/resume/rewind/loop/stop

**Files:**
- Modify: `lib/draw_music_web/live/editor_live.ex`
- Modify: `lib/draw_music_web/playback_payload.ex` (adds `loop?`)
- Modify: `lib/draw_music_web/components/palette_components.ex` (the
  transport)
- Modify: `assets/js/score_editor/index.js` (Home, L, Esc while playing)
- Test: `test/draw_music_web/live/editor_play_test.exs`

**Interfaces:**
- **Consumes:** `Playback.events/3` (`from:`, `to:`), Task 4's push names.
- **Produces:**
  - assigns `playback: :idle | :loading | :playing | :paused`, which
    replaces `playing?`, and `loop?: boolean`;
  - `%PlaybackPayload{events, loop?}`;
  - the palette attrs `playback:` and `loop?:`, which replace `playing?`;
  - `play_span(Session.t()) :: {from, to | nil}` (private).

- [ ] **Step 1: Write the failing tests** (in the existing `editor_play_test.exs`,
  using its setup):
  - `"a range selection plays only that range"`: add G4 at 1920, then
    `select` the C4 and E4 ids; Play pushes `play` with 2 events.
  - `"a single selection plays from it to the end"`: select E4; the events
    are E4 and G4.
  - `"Play while playing pauses; again resumes"`:
    - the pushes are `pause`, then `resume`;
    - `#palette-play` reads "Pause", then "Resume", then "Pause".
  - `"Rewind pushes rewind; Loop toggles and pushes loop"`:
    - `#palette-rewind` pushes `rewind`;
    - `#palette-loop` pushes `loop %{on: true}` and gets
      `aria-pressed=true`.
  - `"Esc while playing stops"`: `render_hook(view, "stop", %{})` pushes
    `stop`, and the state goes to idle.
  - `"an edit while paused stops playback"`: play, pause, then `place` a
    note; `stop` is pushed and the button reads "Play".
  - `"nothing to play stays idle with a message"`: select only a rest
    (insert one with `toggle_rest` and `place`); Play pushes nothing and
    the flash reads "Nothing to play here."
  - Update the existing tests: `aria-pressed` now reflects `:playing`.
- [ ] **Step 2:** Run `mix test test/draw_music_web/live/editor_play_test.exs`.
  Expected: the new tests FAIL.
- [ ] **Step 3: Implement.**
  - One `handle_event("play", …)` clause per playback state (pattern
    matched on `playback:`).
  - **The span:** with 2 or more selected, from the minimum start to the
    maximum `start + ticks`; with 1, `{start, nil}`; with none, `{0, nil}`.
  - `apply_edit/2` pushes `stop` and sets `:idle` when the playback state
    isn't `:idle`.
  - `playback_state` from the hook sets the assign (`"loading"`, `"playing"`,
    `"paused"`, `"idle"` mapped through a function-head lookup, never
    `String.to_atom`).
    - `"fallback"` keeps the state and flashes "<instrument name> isn't
      available; playing with the built-in synth."
    - Test: `"a fallback from the hook shows a notice naming the instrument"`.
  - **The palette:** `palette-rewind` (`hero-backward-solid`) and
    `palette-loop` (`hero-arrow-path`, `aria-pressed`). The label follows
    the state: Play, Pause, Resume, or "Loading <name>…".
  - **Hook keys:** Home → `rewind`, `l` → `toggle_loop`, Escape while the
    `Audio` state is playing or paused → `stop`, checked before disarm.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Manual check: Pause and Resume continue from the same
  note, Loop repeats the range, and Home restarts.
- [ ] **Step 6:** `jj commit -m "Transport: pause, resume, rewind, loop, range playback"`,
  then move the bookmark.

### Task 6: Play mode and audition

**Files:**
- Modify: `lib/draw_music/music/playback.ex` (`chord_at/3`)
- Modify: `lib/draw_music_web/live/editor_live.ex`
- Modify: `lib/draw_music_web/components/palette_components.ex` (the mode
  toggle; the editing groups disabled in play mode)
- Modify: `assets/js/score_editor/index.js` (`data-mode`, the play-mode
  click and drag, the **P** key, the `.play-mode` class)
- Modify: `assets/css/app.css` (the `.play-mode` cursor, a speaker icon
  as a CSS cursor `url()` built by the hook like the armed-glyph cursor)
- Test: `test/draw_music/music/playback_test.exs`,
  `test/draw_music_web/live/editor_mode_test.exs`

**Interfaces:**
- **Consumes:** Task 5's assigns and pushes.
- **Produces:**
  - `Playback.chord_at(Score.t(), Context.t(), Ecto.UUID.t()) :: [PlaybackEvent.t()]`:
    every note on the same staff with the same absolute start as `id`,
    with `start: 0.0`, and `[]` for an unknown id or a rest;
  - the assign `mode: :edit | :play`;
  - the events `toggle_mode` and `audition %{"id" => id}`;
  - the push `audition %{events: [...]}`.

- [ ] **Step 1: Write the failing tests.**
  - `playback_test.exs`, `"chord_at sounds the chord on one staff, with the key's accidentals"`:
    - in G major, place G4+B4+D5 treble at 0, G2 bass at 0, and F4
      treble at 960;
    - `chord_at` on the B4 gives the midis `[67, 71, 74]`;
    - on the F4 it gives `[66]`;
    - a rest id gives `[]`.
  - `editor_mode_test.exs`:
    - `"toggle_mode switches, disarms, and keeps the selection"`:
      - lock a quarter and select a note;
      - click `#palette-mode-play`: `armed` is nil, the selection is
        unchanged, and `#score-editor[data-mode=play]`.
    - `"editing events change nothing in play mode"`:
      - for each of `place`, `move`, `delete`, `cut`, `paste`, `undo`,
        `tie`, `toggle_dot`, `arm_value` and `open_menu`, send it with
        valid params;
      - `notes_of(view)`, `session.history` and `armed` are unchanged.
    - `"Play, Rewind, Loop and Stop still work in play mode"`: `play`
      pushes `play`, and `stop` pushes `stop`.
    - `"audition pushes the chord and selects the note"`:
      `render_hook(view, "audition", %{"id" => id})` pushes `audition`
      with the chord's midis, and the selection is `[id]`.
    - `"the palette's editing groups are disabled in play mode"`:
      `#palette [data-group=notes] button[disabled]` is present.
- [ ] **Step 2:** Run `mix test test/draw_music/music/playback_test.exs
  test/draw_music_web/live/editor_mode_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - **The guard:** one clause before the edit handlers,
    `def handle_event(event, _params, %{assigns: %{mode: :play}} = socket) when event in @edit_events, do: {:noreply, socket}`,
    with `@edit_events` a module attribute listing every editing event
    name.
  - **The hook in play mode:**
    - a click on a note sends `audition`;
    - a drag sends `select_range`;
    - no ghost note, tie gesture or edit keys;
    - **P** sends `toggle_mode` in both modes.
  - The server plays `audition` with `Audio.audition(events)`, which
    starts them immediately without highlights or a state change.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Manual check: in Play mode, clicking sounds the chord,
  the cursor is the speaker, and dragging selects without moving
  anything.
- [ ] **Step 6:** `jj commit -m "Play mode and audition"`, then move the
  bookmark.

### Task 7: Credits page and footer

**Files:**
- Create: `lib/draw_music_web/credit.ex` (`%Credit{work, holder, license, license_url, source_url, use}`)
- Create: `lib/draw_music_web/live/credits_live.ex`
- Modify: `lib/draw_music_web/router.ex` (`live "/credits", CreditsLive`
  in the existing `live_session :current_user` block, in the
  `[:browser]` scope, so it works signed out)
- Modify: `lib/draw_music_web/components/layouts.ex` (a footer with
  `footer-credits` and `footer-help`, the help link pointing at `/help`
  for Task 8)
- Modify: `THIRD_PARTY_NOTICES.md`
- Test: `test/draw_music_web/live/credits_live_test.exs`

**Interfaces:**
- **Produces:** `CreditsLive.credits() :: [Credit.t()]`, in the order
  Bravura, SMuFL glyph names, Tone.js, smplr, MusyngKite soundfonts,
  Splendid Grand Piano, ex_midi.

- [ ] **Step 1: Write the failing tests.**
  - `"renders signed out with every credit"`:
    - `live(build_conn(), ~p"/credits")` succeeds;
    - there's a `#credit-<n>` element for each of the 7 credits;
    - the MusyngKite entry links to
      `https://creativecommons.org/licenses/by-sa/3.0/`.
  - `"the footer links to Credits"`: `has_element?(view, "#footer-credits[href='/credits']")`
    on `/`, signed in.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The MusyngKite text is verbatim from the spec.
  - `THIRD_PARTY_NOTICES.md` gains the same 5 entries it lacks (Tone.js,
    smplr, MusyngKite, Splendid, ex_midi).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** `jj commit -m "Credits page and footer"`, then move the
  bookmark.

### Task 8: Cheat-sheet (`/help` and the editor's **?** dialog)

**Files:**
- Create: `lib/draw_music_web/shortcut.ex` (`%Shortcut{group, keys, mouse, modes, action}`)
- Create: `lib/draw_music_web/shortcuts.ex`
- Create: `lib/draw_music_web/components/help_components.ex`
- Create: `lib/draw_music_web/live/help_live.ex`
- Create: `assets/js/score_editor/keys.json`, a JSON array of every
  `KeyboardEvent.key` value the hook handles (lowercased letters,
  `"ArrowUp"`, `" "`, `"Home"`, `"Escape"`, `"Delete"`, `"Backspace"`,
  `"Insert"`, `"1"`…`"7"`, `"."`, `"?"`, and the Ctrl combos as
  `"ctrl+z"` and so on)
- Modify: `assets/js/score_editor/index.js` (imports `keys.json` and
  ignores any key not in it; **?** opens help)
- Modify: `lib/draw_music_web/router.ex` (`live "/help", HelpLive` in
  `live_session :current_user`)
- Modify: `lib/draw_music_web/live/editor_live.ex` (`palette-help`
  button, `#help-dialog`, the `open_help` and `close_help` events)
- Test: `test/draw_music_web/shortcuts_test.exs`,
  `test/draw_music_web/live/help_live_test.exs`

**Interfaces:**
- **Produces:**
  - `Shortcuts.all() :: [Shortcut.t()]`;
  - `Shortcuts.groups() :: [String.t()]`: Placing, Selecting and
    moving, Ties and chords, Measures, Editing, Saving, Playback, Modes;
  - `Shortcuts.for_mode(:edit | :play) :: [Shortcut.t()]`, the mode's
    own entries first;
  - `Shortcuts.handled_keys() :: [String.t()]`, every key named in
    `all/0`;
  - `<HelpComponents.cheat_sheet shortcuts={...} />`;
  - one diagram component per gesture: `ghost_snap/1`,
    `accidental_modifiers/1`, `tie_drag/1`, `rubber_band/1`,
    `insert_shift/1`, `play_cursor/1`, `range_playback/1`, `loop/1`.
    They are drawn with `ScoreComponents` pieces on a short staff and use
    `--score-ink`.

- [ ] **Step 1: Write the failing tests.**
  - `"every key the editor handles is on the cheat-sheet"`:
    - `"assets/js/score_editor/keys.json" |> File.read!() |> JSON.decode!() |> MapSet.new()`
      is a subset of `MapSet.new(Shortcuts.handled_keys())`;
    - and the reverse, so neither list has entries the other lacks.
  - `"every Phase 4 and 5 mouse gesture has an entry"`: the `mouse`
    fields include
    - `"click staff"`, `"shift-click"`, `"ctrl-click"`,
    - `"drag note to note"`, `"drag empty area"`,
    - `"right-click"`, `"double-click palette item"`,
    - `"click note (Play mode)"`, `"drag (Play mode)"`.
  - `"/help renders signed out with all groups and diagrams"`:
    - each group heading is present;
    - `#diagram-tie-drag` and `#diagram-rubber-band` are present.
  - `"? opens the help dialog in the editor and Esc closes it"`:
    `render_hook(view, "open_help", %{})` shows `#help-dialog`, and
    `close_help` hides it.
  - `"in Play mode the dialog lists Playback and Modes first"`: the first
    group heading in `#help-dialog` is "Playback".
- [ ] **Step 2:** Run `mix test test/draw_music_web/shortcuts_test.exs
  test/draw_music_web/live/help_live_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Write the entries from the hook's current `key()`, the mouse
    handlers, and Tasks 5–6.
  - The Phase 4 entries come from `plans/phase-4-editing.md`,
    "Interactions".
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Manual check: the diagrams read correctly in light and
  dark themes, with a custom dark ink.
- [ ] **Step 6:** `jj commit -m "Cheat-sheet: /help and the editor's help dialog"`,
  then move the bookmark.

### Task 9: Wrap-up

- [ ] **Step 1:** Run `mix precommit`. Expected: clean, with all tests
  passing.
- [ ] **Step 2:** Run the manual checklist in the spec's Verification
  section, Safari included, if one is available. Record anything skipped
  in the ledger.
- [ ] **Step 3:** In `plans/draw-music-plan.md`, mark Phase 5 done with
  the date, and list anything deferred.
- [ ] **Step 4:** `jj commit -m "Plans: phase 5 done"`, then
  `jj bookmark set Phase-5 -r @-`. Don't push; the user decides.
