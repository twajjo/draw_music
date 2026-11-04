# Large scores (Phase 7)

## Problem
*Rhapsody in Blue* has 460 bars, about 80,000 drawn items and an 8.5 MB SVG. Three things make it slow:
1. **The server builds the SVG from about 80,000 HEEx component calls.** That's 1.5–2 s on every render.
2. **The whole SVG is one raw string**, so any change resends all 8.5 MB. That includes a selection change, because the `.selected` classes are baked into it.
3. **The browser lays out and paints the whole score**, including what's off-screen.

## Approach

### 1. Render the SVG as iodata (`DrawMusicWeb.ScoreSvg`, new)
- Plain functions turn `Engraved` items into iodata: `<text>`, `<line>`, `<polygon>`, `<path>`, the brace and tempo marks. They take over `ScoreComponents.item/1`'s output attribute for attribute, minus the selection class.
- Text is escaped with `Phoenix.HTML.html_escape/1`. Only tempo labels carry user text.
- `ScoreComponents.score/1` and `systems/1` become thin wrappers over it, so the SVG export (`score_export.ex`) uses the same output.
- Item output is checked against the current HEEx output in a test, so nothing drawn changes.

### 2. The score in pieces, one `<svg>` per piece
- **Engraving:** `Layout.stack/1` already works out each system's band: from the previous system's end, through the space above, the staff, the space below and the gap. `System` gets that band as `top` and `bottom`, so the bands tile the page with no overlap.
- **Page layout:** one piece per system.
  - Its `viewBox` is the band, in the score's own page coordinates: `-pad top W (bottom - top)`. The system's `<g transform="translate(0 y)">` stays as it is.
  - Pieces stack in a column with no gaps. Each one's `aspect-ratio` is set from its band, so their heights add up to the whole score's.
- **Strip layout:** one system, cut into pieces of about 16 bars at barlines.
  - Each piece's `viewBox` is its x range.
  - Glyphs (noteheads, rests and the rest) go to the one piece that holds their x, so ids stay unique.
  - Lines, beams, ties and tempo marks go to every piece they cross; each piece clips its own share. Tempo-mark ids move to `data-tempo-id`, which the hook already uses for hit-testing.
- **Wrappers:** each piece sits in a `div.score-piece` with `content-visibility: auto` and a `contain-intrinsic-size` from its pixel size, so the browser skips laying out and painting the pieces it can't see.
- **Keyed comprehension:** the pieces are rendered with `:for … :key={piece.key}`, LiveView 1.2's keyed comprehension. An edit then resends only the pieces whose items changed, and a change that moves nothing sends nothing.
- **Coordinates:** the overlay `<svg>` keeps the whole score's `viewBox` and covers every piece. `toScore` changes from `#score`'s CTM to the overlay's, so pointer → score coordinates work as before.
- **Hook changes for pieces:**
  - `this.score` stops being one element.
  - The selector at index.js:394 searches `#score-editor`.
  - The system for a dragged note comes from `data-system` on its `<g>`, not the `system-N` id, which would repeat across Strip pieces.

### 3. Selection per piece (changed while building)
- Each piece carries the ids of its own selected items (`ScoreSvg.select/2`). LiveView change-tracks each entry of the pieces comprehension, so a selection change re-renders and resends only the pieces whose selection changed.
- That keeps `.selected` server-rendered: no browser-side selection code, and the existing selection tests still hold.
- Select-all still resends everything.

### Built 2026-10-29
On the 460-bar score (about 90,000 items):
- **A full SVG render** (the join, or a layout switch) takes about 0.4 s in Page layout and 0.2–0.3 s in Strip, against 1.5–2 s before. An edit or a selection change renders only the pieces it changes.
- **Engraving (`Layout.layout/3`)** takes 0.5–1 s and now dominates every edit. It's the next thing to look at if editing a long score still feels slow.

## Files
- **New:** `lib/draw_music_web/score_svg.ex`.
- **Changed:**
  - `score_components.ex` (wrappers)
  - `layout.ex` and `system.ex` (bands)
  - `editor_live.ex` (pieces, `data-selection`, no selection in `score_svg`)
  - `score_export.ex`
  - `assets/js/score_editor/index.js` (`toScore` via the overlay, the selection pass, the selectors above)
  - `app.css`

## Verification
- **Tests:** item iodata matches the old HEEx output; the bands tile the page with no gaps; Strip pieces cut at barlines with every glyph in exactly one piece; the selection goes out as `data-selection`, and a selection change doesn't resend pieces.
- **Timing:** time `Layout` and render for *Rhapsody in Blue* before and after, using an IEx script on the imported version.
- **Manual (user):** open the large score in both layouts. Scroll, click and drag notes, rubber-band select, place and delete notes, and play with the playhead following. Switch layout, and check that the SVG export is unchanged.
