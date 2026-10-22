# Phase 3: read-only rendering + SVG export

## Context
Phases 1–2 built the Library (compositions → keys → versions) and the pure
music domain. Nothing is visible yet. Phase 3 draws a version's score as SVG
with Bravura glyphs, adds the pages needed to reach it, exports SVG, and adds
two per-user display preferences:
- the score layout (one long staff, or page-style systems);
- the dark-mode ink color, under the score color scheme decided 2026-10-21:
  follow the app's light/dark theme, and export always black on white.

## Decisions (2026-10-22)
- **Layout is a user preference** (`users.score_layout`, `:strip | :page`, default `:strip`):
  - **Strip:** the whole piece as one long, horizontally scrolling grand staff.
  - **Page:** measures wrapped into systems at a fixed page width, the same layout as the SVG export, scaled to fit the window.
  - Both come from one layout engine; the only difference is the system width (`:infinity` vs the page width).
  - The SVG export is always page layout.
  - Set from a toggle in the score view toolbar (which saves the preference) and in Settings. Phase 4's editor works the same way in either layout: every measure records its own x and tick scale.
- **Bravura:** vendored, pinned to release `bravura-1.482`. Read at compile time (`@external_resource`), so builds need no network.
  - `priv/static/fonts/Bravura.woff2` and `priv/static/fonts/OFL.txt`
  - `priv/smufl/Bravura.json`: engraving defaults and glyph bounding boxes
  - `priv/smufl/glyphnames.json`: from w3c/smufl
- **URL:** `/compositions/:id/:key/v/:number`, where `:key` is a slug such as `g-major`, `f-sharp-minor` or `b-flat-major`.
- **Pages:** library list, new composition form, and a read-only score view with SVG download. Upload/import stays in Phase 6, editing in Phase 4.

## Engraving (pure): `lib/draw_music/engraving/`
- **`Smufl`:**
  - glyph name → character, covering only the glyphs we use (checked at compile time);
  - engraving defaults: staff line, stem, beam and ledger thicknesses;
  - the bounding boxes we need: notehead widths for stem attachment, and accidental widths.
- **`Layout.layout(score, ctx, opts)`** returns `%{width, height, systems: [...]}`. Units are staff spaces; the components scale them.
  - **Options:** `width` (`:infinity` or the page width) and `spacing` (staff spaces per quarter note, i.e. zoom).
  - **Vertical:** `y(staff, step)`, computed per staff.
    - The treble top line is F5 and the bass top line is A3, with a fixed gap between the staves.
    - Top and bottom margins grow to fit the highest and lowest notes (up to C8, down to A0) with their ledger lines.
  - **Horizontal:** proportional spacing.
    - Within a measure, `x = left_pad + offset × spacing`; `left_pad` leaves room for accidentals.
    - A measure is `left_pad + capacity × spacing + right_pad` wide.
    - Each measure records its `x`, `start_tick` and scale, so a pointer position maps back to a tick in either layout.
  - **Items in each measure:**
    - noteheads by value (whole, half, black) and dots;
    - accidentals from `Accidentals.displayed/3`, offset left and staggered within a chord;
    - ledger lines;
    - stems: direction from `Stems.direction/4`, 3.5 spaces long, lengthened to reach the middle line;
    - flags, or beams from `Beaming.groups/3` with the slope clamped;
    - rests by value, centered. A staff with nothing in a measure gets a whole-bar rest;
    - ties: arcs to the target note. A tie crossing a system break becomes two half arcs;
    - bar lines, and a final double bar.
  - **System header:** brace, clefs, key signature (sharp and flat staff positions per clef), and the time signature (digits, or the common/cut glyphs) on the first system only.
  - **Page mode:** measures are packed greedily into systems no wider than `width`, and each system is stretched to fill it.
- **`Key.slug/2` and `Key.from_slug/1`** for the URL.

## Web
- **Routes:** all in the existing `:require_authenticated_user` scope and `live_session`, because every page shows the signed-in user's own compositions.
  - `live "/compositions", LibraryLive, :index`: the user's compositions, each with its keys and versions, linking to the score view. Uses a stream.
  - `live "/compositions/new", NewCompositionLive, :new`:
    - fields: name, credits, key, time signature and symbol, tempo, pickup;
    - creates v1 with `Score.new(4)` through `Library.create_composition/4`, then navigates to the score view.
  - `live "/compositions/:id/:key/v/:number", EditorLive, :show`: read-only for now.
    - A header with the title, credits, key and a version picker.
    - A toolbar with the Strip/Page toggle and a "Download SVG" link.
    - The score itself.
  - `get "/compositions/:id/:key/v/:number/score.svg", ExportController, :svg`
- **`Library.get_version_by_number!(scope, composition_id, {sf, mode}, number)`:** scoped to the user; preloads the key and composition.
- **`ScoreComponents`** (function components, per the components-first rule):
  - `score`, `system`, `staff_lines`, `header` (brace, clef, key and time signatures), `measure`;
  - `note` (`id="note-<id>"`), `rest`, `beam`, `tie`, `ledger_lines`, `barline`;
  - an `ink` assign: `var(--score-ink)` on screen, `#000` in print.
- **`LibraryComponents`:** the composition row and the key/version list.
- **`SettingsComponents`:** the layout toggle and the ink swatches. Each is used both in Settings and in the score view toolbar.
- **SVG export:**
  - the same components in print mode, in page layout;
  - title and credits above the music, on a white background;
  - Bravura embedded as base64 in an `@font-face` (read at compile time);
  - served as `image/svg+xml` with a download filename such as `Waltz - G major - v2.svg`.
- **User preferences** (one migration on `users`):
  - **`score_layout`:** `Ecto.Enum [:strip, :page]`, default `:strip`.
  - **`score_ink_dark`:** a string, nullable (nil means white).
  - `User.preferences_changeset/2` casts both and checks the color: `#rrggbb` format, and a WCAG contrast of at least 7:1 against black.
  - `Accounts.update_user_preferences/2` saves them.
- **Score colors:**
  - In `app.css`, `--score-ink` and `--score-paper` (plus selection, ghost-note and playback-highlight colors for later) are set per theme.
  - The dark theme (an explicit `[data-theme=dark]`, or system mode when the OS prefers dark) uses `var(--score-ink-dark, #fff)`.
  - The root layout sets `--score-ink-dark` on `<html>` from `@current_scope.user`.
  - The settings page gets a "Score display" section: the layout choice, plus swatches (white, cream, amber, light green, light blue, light pink) and a custom color input.
  - Saving a color updates the variable live with `JS.set_attribute(..., to: "html")`, so no custom JS is needed.
- **Attribution:** `THIRD_PARTY_NOTICES.md` gains Bravura (SIL OFL 1.1). The footer Credits page comes in Phase 5, together with the samples.

## Tests (functionality only)
- **Layout:**
  - y positions: middle C gets one ledger line on either staff;
  - key signature glyph count and positions;
  - stems follow `Stems`, and beams follow `Beaming`;
  - an empty staff gets a whole-bar rest;
  - accidentals honor ties into the measure;
  - each measure's tick ↔ x mapping round trips.
- **Strip vs page:**
  - strip is a single system holding every measure;
  - in page mode no system exceeds the width, only the first system has a time signature, and a tie across a break gives two half arcs.
- `Key.slug/2` ↔ `Key.from_slug/1` round trips for all 30 keys.
- **`User.preferences_changeset/2`:**
  - accepts `#ffcc66`;
  - rejects `#333333` (contrast) and `ffcc66` (format);
  - accepts only `strip` and `page` as layouts.
- **LiveViews and controller:**
  - the list shows only the user's own compositions;
  - the new form validates, creates, and lands on the score view;
  - the score view renders `#score` and `#note-<id>` in the user's preferred layout;
  - the layout toggle switches the layout and saves the preference;
  - another user's version raises a 404;
  - the SVG download is `image/svg+xml` in page layout and contains `@font-face`;
  - saving the score preferences on the settings page persists them.

## Verification
- `mix precommit` is clean.
- Manual (`mix phx.server`):
  - Create a composition and open it: an empty grand staff with whole-bar rests.
  - Insert a demo score via `iex -S mix phx.server` with `Editing` calls, then check beams, stems, ties, accidentals and ledger lines in both Strip and Page layouts.
  - Reload: the chosen layout persists.
  - Toggle Light/Dark, then pick amber ink.
  - Download the SVG and open it in a browser without Bravura installed.
- jj: one described change for the phase, with `master` moved onto it.
