# Phase 8: Live MIDI keyboard input

## Context
Play notes from a connected MIDI keyboard into the score, like step entry in notation software. Decided with the user on 2026-10-29:
- **A visible insertion cursor** marks where entry goes and steps forward after each entry.
- **A fixed staff split** at middle C: C4 and above go on the treble staff, below it on the bass.
- **Length** comes from a preference: the palette's **picked** value, or how long the key is **held** (quantized).
- **Rests and dots** use the computer keyboard while playing: **R** switches the palette to rests, after which a key press enters a rest; **.** dots; **1–9** pick the value.
- **In Play mode** the keys only sound; nothing is written.
- Optional extra: Chromium browsers support Web MIDI, Firefox asks permission, Safari has none. Without it the MIDI controls don't show.

## Design

### Browser (`ScoreEditor` hook, new `assets/js/score_editor/midi.js`)
- **WEBMIDI.js** (`webmidi` on npm) handles enabling Web MIDI, listing inputs, connect and disconnect, and note on/off.
- **Sound:** each key sounds at once through the playback instrument (`Audio.audition`, local, with no round trip) in both modes.
- **Chords:** presses within **50 ms** of the first one form one chord.
  - **Picked length:** the chord is sent 50 ms after its first press.
  - **Held length:** it's sent when the last key of the chord is released, with `held_ms` measured from the first press.
- **The event:** the hook sends `play_keys` with `notes` (MIDI numbers) and, in held mode, `held_ms`. Edit mode only.
- **The cursor:** a caret line in the overlay at `data-cursor` (a tick), drawn with `playheadAt` in the selection colour so it reads differently from the red playback line. It shows in Edit mode while MIDI entry is on.

### Server
- **The cursor:** a new assign `:cursor` holds a tick.
  - Clicking empty music sets it; this replaces `last_click`, so paste uses the same point.
  - Selecting one note or rest puts it just after that note or rest.
  - Each entry moves it on by the length entered.
  - Undo and redo leave it where it is, clamped to the score's end.
- **`play_keys`**, through a new `DrawMusicWeb.KeyEntry`:
  1. **Spelling:** `Pitch.spell/2` gives each MIDI number its step and alteration in the key.
  2. **Staves:** split at middle C (MIDI 60 and above go on the treble staff).
  3. **Length:**
     - Picked mode uses the armed value and dots, or a quarter if nothing is armed.
     - Held mode turns `held_ms` into ticks with the tempo at the cursor (`TempoMap`). It picks the nearest single value, dots allowed, from a whole note down to a 16th. Anything longer is a whole note, and the shortest is a 16th, so uneven playing doesn't produce 64ths.
  4. **Placing:** a note, or a chord (`Editing.place_chord`) on each staff that has notes, at the cursor. In rest mode a key press places a rest of that length on the treble staff and the pitch is ignored.
     - The existing rules apply: Insert makes room on each staff that receives notes, Overlay replaces the time covered, entries may cross bar lines, and new bars are added past the end.
     - One key press is one undo step.
  5. **The cursor moves on** by the length entered.
- **The length preference:** a new user field `midi_length` (`:picked` or `:held`, default `:picked`), added with `mix ecto.gen.migration`. It's set through `ScorePreferences` from the MIDI menu and the settings page.

### Palette (`PaletteComponents`)
A MIDI button in Edit and Play modes. It's hidden without Web MIDI and shows whether a device is connected. It opens a small menu:
- an on/off toggle (turning it on asks the browser's permission);
- an input picker;
- the picked/held length choice.

## Files
- **New:**
  - `assets/js/score_editor/midi.js`
  - `lib/draw_music_web/key_entry.ex`
  - a migration
  - tests
- **Changed:**
  - `assets/js/score_editor/index.js` (MIDI, the cursor caret)
  - `assets/package.json` (webmidi)
  - `editor_live.ex` (`:cursor`, `play_keys`)
  - `palette_components.ex`
  - `accounts/user.ex` (`midi_length`)
  - `score_preferences.ex`
  - the settings page
  - `shortcuts.ex` and `help_components.ex` (cheat-sheet entries and a diagram)

## Style sweep (from the Phase 5 code review)
Every anonymous function bound to a variable is written multiline, however short its body:

```elixir
room = fn ticks ->
  max(@min_note_space, ticks * scale)
end
```

- `fn` and its arguments go on the assignment line, the body is indented below, and `end` sits on its own line aligned with the variable.
- Inline `fn ... end` stays only where it's passed literally as an argument.
- Convert the 13 existing one-liners. They're in `pitch.ex`, `tempo_map.ex`, `duration.ex` (2), `notes.ex` (2), `layout.ex`, and the tests. Also fix any multiline ones whose `end` isn't aligned with the variable.
- New Phase 8 code follows the rule from the start.

## Split `Editing` (from the Phase 5 code review)
`editing.ex` is 1,404 lines, with 32 public and 73 private functions. The full plan is in `plans/editing-module-review.md`.

The work comes before the MIDI entry code, so `KeyEntry` builds on the new modules:
1. Pull out the pure helpers: `Spans`, `Ties`, `Fillers`, `Rebuild`.
2. Remove the redundancies.
3. Split the edits by topic, behind a short `Editing` facade.
4. Order public functions first and private functions last in each new module.

Each step is a separate jj change with `mix precommit` clean, and behaviour stays the same.

## Break up the palette (from the Phase 5 code review)
`palette/1` is one 389-line block of HEEx. The plan is in `plans/palette-component-review.md`: compose it from named sub-components, and split the module into edit tools, transport and glyphs.

Do this before adding the MIDI button and menu, so they become their own `midi_menu/1` sub-component rather than more lines in the blob.

## Break up `EditorLive` (from the Phase 5 code review)
The strategies are in `plans/editor-live-review.md`: feature event modules attached with `attach_hook/4`, LiveComponents for the form dialogs, a single `:dialog` assign, grouped assigns and a composed `render/1`. Nested LiveViews are out. The new `play_keys` event and the cursor go into their own modules from the start.

## Delivery: small PRs, merged a little at a time (from the Phase 5 review)
Phases 5, 6 and 7 had 104, 53 and 57 files per PR. That is far too many to review.

- Phase 8 ships as many small PRs, each one piece of functionality and **about 10 files at most**, kept simple enough to review in one sitting.
- Every push gets its own PR, opened right after the push. Each one is reviewed and merged before the next push, so there are no long stacks.
- Refactors are never mixed with features.
- If a piece grows past about 10 files, split it further before pushing.

| PR | Contents |
|---|---|
| 8.1 | Fix: dropdown menus close when you click away or press Escape (see below) |
| 8.2 | Top bar: a **Settings** page for score display; the account menu's "Settings" becomes **Account** (see below) |
| 8.3 | Score paper: a user default, independent of the interface theme (see below) |
| 8.4 | Score paper: a per-composition override (see below) |
| 8.5 | The Save menu moves to the top bar (after 8.1, which fixes the dropdown it uses; see below) |
| 8.6 | Import .mid from the top bar (see below) |
| 8.7 | The DrawMusic wordmark opens an About dialog (see below) |
| 8.8 | Style sweep in `lib/draw_music/music` (assigned `fn`s multiline, public functions first) |
| 8.9 | Style sweep in `lib/draw_music/engraving`, the MIDI code and the library code |
| 8.10 | Style sweep in `lib/draw_music_web` (non-generated) |
| 8.11 | Style sweep in the tests |
| 8.12 | `Editing`: pull out `Spans` and `Ties` |
| 8.13 | `Editing`: pull out `Fillers` and `Rebuild`; fix the redundancies |
| 8.14 | `Editing`: split the edit groups behind the facade |
| 8.15 | Palette: sub-components and the shared `tool_button` |
| 8.16 | Palette: split the module (edit tools, transport, glyphs) |
| 8.17 | `EditorLive`: move the pure logic out |
| 8.18 | `EditorLive`: the single `:dialog` assign |
| 8.19 | `EditorLive`: the form dialogs as LiveComponents |
| 8.20 | `EditorLive`: the event modules with `attach_hook` |
| 8.21 | `EditorLive`: grouped assigns, composed `render/1` |
| 8.22 | The insertion cursor (server, caret, cheat sheet) |
| 8.23 | MIDI in the browser: WEBMIDI.js, the device menu, sounding the keys |
| 8.24 | MIDI into the score: `KeyEntry`, `play_keys`, the `midi_length` preference (on the 8.2 Settings page), the cheat sheet |

The sweeps (8.8–8.11) are split further if any area turns out to be over about 10 files.

## The wordmark opens About (requested 2026-11-06)
**Now:** the DrawMusic wordmark in the header (`Layouts.app`) is a `<.link navigate={~p"/"}>`, the same as **New**. It opens a blank composition, and from the editor it throws away the score that's open. The user reports that it logs them out.
- Nothing in the code logs out on that link. The only log-out is `DELETE /users/log-out` in the account menu.
- So reproduce it first, with the user running the server: which page it was clicked from, and whether the log-in page appears.
- A plausible cause is that `/credits` and `/help` are in the `:current_user` live_session and `/` is in `:require_authenticated_user`, so crossing between them does a full page load. That shouldn't drop the session, but it needs checking.

**Wanted:** clicking the wordmark shows basic information about the application instead of navigating.

**The design:**
- **An About dialog**, a function component `about_dialog/1` in `Layouts`, rendered once by `Layouts.app`. The wordmark becomes a button that shows it with `JS.show`. There's no navigation and no server round trip, so unsaved work in the editor is safe, and it works on every page, signed in or not.
- **It closes** on its close button, Escape, or a click outside (`phx-click-away`), matching the dropdown fix in 8.1.
- **It shows:**
  - DrawMusic and its version (`Application.spec(:draw_music, :vsn)`, now 0.1.0);
  - the author: Jeff Osborn;
  - the application's own licence, with its text or a link;
  - a link to **Credits** for the fonts, libraries and samples and their licences.
- **A `LICENSE` file** at the project root holds the application's licence. The About dialog and `mix.exs` (`package`/`licenses`) refer to it.
- **New** stays the way to open a blank composition.

**Decided (2026-11-06):**
- **The licence is MIT.** Add a `LICENSE` file at the project root with the standard MIT text, `Copyright (c) 2026 Jeff Osborn`, and set `licenses: ["MIT"]` in `mix.exs`. The About box names the licence and shows its text, or links to the file.
- **The author line:** "© 2026 Jeff Osborn, with the assistance of Anthropic Claude (Claude Opus 5.5)". The model name is the version information the user asked for, written as plain text in the component. If later work is done with another model, the line is updated then.

**Tests:**
- The wordmark no longer links to `/`.
- The dialog renders with the author, version, licence and the Credits link (by element ids: `#about-dialog`, `#about-licence`, `#about-credits`).
- The user checks in the browser that it opens from the editor without losing unsaved changes, and that it closes on Esc and on a click away.

## Fix: dropdowns that won't close (reported 2026-11-05)
**The bug:** the Save dropdown (the chevron beside Save) stays open when you click elsewhere. The only way out is to click the chevron again or to pick a save, so you can't leave the menu without saving.

**The cause:** it's a native `<details>` element, which stays open until its own `<summary>` is clicked. Nothing closes it on an outside click or on Escape. Two other menus are built the same way and have the same problem:
- the palette's Chords menu (`#palette-chords-menu`);
- the dropdown in `LibraryComponents` (line 281).

**The fix:**
- Add one shared `<.dropdown id=...>` component, with `summary` and item slots, wrapping the `<details>`. It closes the menu by removing its `open` attribute (`JS.remove_attribute("open")`) on:
  - a click outside it (`phx-click-away`);
  - Escape (`phx-window-keydown` with `phx-key="Escape"`);
  - choosing an item, by chaining `JS.remove_attribute("open", to: "#id")` before the item's push.
- Use it for all three menus.
- Keep the ids, so the tests and shortcuts don't change.
- Add a cheat-sheet line: "Esc or click away closes a menu".

## Score paper separate from the interface theme (requested 2026-11-06)
**Now:** the score's colours follow the interface theme. `.score-colors` in `app.css` is black on white, and `[data-theme=dark] .score-colors` is the user's dark ink (`score_ink_dark`, white by default) on black. So a dark interface always means dark paper.

**Wanted:** the score paper (black on white, or colour on black) and the interface theme are two unrelated settings. A dark interface can show classic white sheet music, and a light interface can show dark sheet music. The paper is a user default that a composition can override. There is no "Follow theme" option (decided 2026-11-06).

**The design, PR 8.3 (the user default):**
- **The preference:** a new user field `score_paper`, an `Ecto.Enum` of `[:light, :dark]`, default `:light` (black on white). It's added with `mix ecto.gen.migration` and cast in `User.preferences_changeset`. Users who now see a black score under a dark interface will see white until they choose Dark. Say so in the PR description.
- **Saving it:** a `set_score_paper` clause in `ScorePreferences.apply_event/3`, next to `set_score_layout` and `set_score_ink`.
- **The CSS** (`app.css`): `Layouts.app` puts `data-score-paper` on the `.score-colors` element (`<main>`), next to the ink style.
  - `.score-colors` keeps the light tokens.
  - `[data-theme=dark] .score-colors` becomes `.score-colors[data-score-paper=dark]`. It's the dark tokens with the user's dark ink (`var(--score-ink-dark, #fff)`).
  - Nothing about the score reads `data-theme` any more. The selection and playhead colours go with the paper, so they stay readable.
- **The control:** a Light / Dark `paper_toggle` in `SettingsComponents`, on the Settings page (8.2) beside the layout toggle. The dark-ink picker is labelled "Ink on dark paper".
- **The exports:** the SVG and PDF downloads keep black on white (`score_export.ex` hard-codes `#fff`/`#000`). They are unchanged.
- **The cheat sheet:** a line saying the default is in Settings and a composition's own is in Details.

**The design, PR 8.4 (the composition override):**
- **The field:** `compositions.score_paper`, `Ecto.Enum` `[:light, :dark]`, nullable; nil means "use my default". It's cast in `Composition.changeset`. That way the Details dialog, Save as, and a draft's first save (`store_details` in `EditorLive`) carry it with no extra plumbing.
- **The paper in use:** a pure function, e.g. `Layouts.score_paper(scope, composition_or_nil)`. It returns the composition's value, else the user's, else `:light`. `Layouts.app` gets an optional `score_paper` attr: the editor passes its composition, and other pages (help) use the user's default.
- **The ink:** the composition overrides only the paper. Colour on black always uses the user's `score_ink_dark`.
- **The control:** a "Score paper: My default (Light) / Light / Dark" select in `LibraryComponents.composition_fields`, so it appears in the Details dialog and in Save as. A saved composition stores it at once, like the other details. It isn't part of the score's undo.

**Tests:**
- 8.3: the user changeset accepts light and dark and refuses others; `set_score_paper` saves; `<main>` carries `data-score-paper` from the user's default.
- 8.4: the composition changeset accepts nil, light and dark; `score_paper/2` prefers the composition's value and falls back to the user's; the editor's `<main>` follows a composition's override.
- The user checks in the browser: dark interface with white paper, light interface with dark paper, and a composition overriding the default.

## Settings in the top bar, Account in the menu (requested 2026-11-06)
**Now:** the score display preferences sit on the account page (`/users/settings`, "Score display" section), reached from the account menu's "Settings" item. That name hides what the page mostly is: account setup (email, password).

**The design (PR 8.2):**
- **A new `DrawMusicWeb.SettingsLive` at `/settings`.** It goes in the existing `live_session :require_authenticated_user` (and its `:require_authenticated_user` pipeline), because preferences belong to a signed-in user.
  - It holds the score display section: the layout toggle now; the paper toggle and ink picker from 8.3; the `midi_length` preference from 8.24.
  - It reuses `ScorePreferences.form/1` and `apply_event/3`.
- **The top bar** (`Layouts.app` nav): New, Compositions, **Settings** (`#nav-settings`), styled the same, so Settings is as easy to find as New.
- **The account menu:** "Settings" becomes **Account** (`#account-menu-account`), linking to `/users/settings` as before. That page keeps email and password only. Its "Score display" section and `set_score_*` handler move to `/settings`. The interface theme toggle stays in the account menu, where it is now.
- **The cheat sheet:** where Settings and Account are.

**Tests:** the header has `#nav-settings`; `/settings` renders the layout toggle and saves a change; the account page no longer has `#score-display`; the menu has `#account-menu-account`.

## Save in the top bar (requested 2026-11-06)
**Now:** Save and its dropdown (`<.save_menu>`) sit in the palette's `:trailing` slot.

**The design (PR 8.5, after the dropdown fix in 8.1):**
- `Layouts.app` gets a `:menu_bar` slot, rendered in the header nav after Settings. The layout is rendered inside the LiveView, so `save`, `save_new_version` and `open_save_as` still reach `EditorLive`.
- `EditorLive.render/1` moves `<.save_menu>` into `<:menu_bar>`, with the Unsaved badge beside it. The ids don't change, so Ctrl+S, the shortcuts and the tests keep working.

**Tests:** the save menu is inside the header, not the palette.

## Import .mid from the top bar (requested 2026-11-06)
**Now:** Import .mid is only a button on `/compositions`, so it's easy to miss.

**The design (PR 8.6):**
- A top-bar **Import** link (`#nav-import`, `hero-arrow-up-tray`) points to a new `/compositions/import` route. It's a second live action, `:import`, of `LibraryLive`, in the same `live_session :require_authenticated_user` as `/compositions`.
- `handle_params` for `:import` opens the existing import dialog (`import_step: :upload`). Closing it patches back to `/compositions`. The upload code stays where it is: no LiveComponent, no duplication.
- Leaving the editor this way follows the same rules as New.

**Tests:** `/compositions/import` mounts with the upload dialog open; the header has `#nav-import`.

**Tests (dropdowns):** the closing is client-side, so the user checks it in the browser. Click away, press Esc and pick an item on each menu, and check that the score isn't saved.

## Tests (server-side logic)
- **`KeyEntry`:**
  - spelling in sharp and flat keys;
  - the middle-C split;
  - a chord across both staves;
  - rest mode;
  - Insert making room on each staff;
  - held-length rounding at two tempos, with the 16th floor and the whole-note cap.
- **Editor:**
  - `play_keys` places notes at the cursor and moves it on;
  - a click sets the cursor, and so does selecting a note;
  - Play mode ignores `play_keys`;
  - the preference saves.
- **Manual (the user, with a keyboard):**
  - Chrome: chords, both lengths, R and . mid-phrase, Play mode sounds only;
  - Firefox's permission prompt;
  - Safari shows no MIDI button.
