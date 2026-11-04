# Insert and Overlay as in a text editor; insertion gaps (2026-10-25)

## Context
The editor's Overlay and Insert behaviour grew case by case, and the result surprised the user. Examples: a quarter stacked onto a half as a second voice, and the Insert preview snapping onto the note it goes in front of. The user's model is a text editor, where time matters in Overlay.

## Rules (agreed with the user)
Every rule applies to every item: notes, placed rests and filler rests alike.

### Insert works like typing in insert mode
- The cursor sits between items: in the gap before an item, or after the last item.
- The new item goes there, and everything after it on the staff moves right by its length.
- Beats are ignored. The only bar-line rules are that notes are tied over a bar line and rests are split at it.
- A click on an item, or in the gap before it, places the new item before that item. A click past the music places it after the last item.
- Rests after the last note of the piece shrink instead of moving, like empty space at the end of a text.

### Overlay works like typing over text, in time
- The new item replaces the time it covers, starting at its position: a half note replaces 2 beats.
  - It replaces notes and rests in every voice on that staff.
  - It can run over a bar line.
- The position snaps to the beat grid.
- A note sounding into the covered time from earlier is shortened.
- The covered part of anything running past the covered time is removed, and the remainder becomes rests.
- Nothing moves left or right.
- There is no chord stacking, no automatic second voice, and no jumping past a note that is still sounding.

### Chords
- Whole chords come from the Chords palette (placing) or chordify (selected notes).
- A note's right-click menu gains **Add 3rd above** and **Add 3rd below**: a diatonic third in the key, added to its chord.

### Layout
- Every drawn item has an insertion gap to its left.
- Bars are spaced in columns shared by both staves:
  - the first column sits one gap in;
  - each next column sits at `x_k + max(min space, ticks × scale) + gap`;
  - a bar is as wide as its columns need, while still holding one bar of beats.
- Ticks map to x piecewise through the columns, on the server and in the hook alike.
- In Insert, the preview sits in the gap and never snaps onto an item.
- In Overlay, the preview sits on the grid position.

## Approach
1. **Overlay replace.**
   - `Placement.overwrite`, set by `EditorPlacement` in Overlay. `Editing.place` clears the covered span on the staff before adding: it truncates items that started earlier and removes the others. Filler refills what's left.
   - Overlay sets `cross_bar` too.
   - Remove `afterSounding` from the hook.
   - Remove the select-on-same-start branch in `EditorLive.place_or_select`.
2. **Chord menu.** `add_third` up/down in `EditorCommands.menu`. It places one note into the clicked note's chord through `Editing.place_note`, at the chord's voice, start and length.
3. **Insert cursor.**
   - `MeasureGeometry.columns`, with `%Column{offset, x, staves}`, spaced as above. `x_at/2` and `offset_at/2` replace the linear map.
   - `Notes` places noteheads and rests through `x_at`.
   - In the hook, `locate` uses the columns. In Insert, a click in a gap or on a column is `ahead` of that column's item on the staff, and the preview is drawn in the gap. Past the last column the click appends.
   - `insert_point/4` counts every rest except trailing filler.

## Tests
- Editing:
  - Overlay: a half note over Q Q replaces both; a quarter over a whole note leaves rests; a note sounding in from earlier is shortened; every voice is cleared; it runs over a bar line.
  - `insert_point` with interior filler versus trailing filler.
- Layout:
  - columns are aligned across staves, and there's a gap before every item;
  - a bar of sixteenths is wider than a bar holding one whole note;
  - `x_at` and `offset_at` round-trip.
- LiveView:
  - Insert ahead of a mid-bar note and ahead of an interior rest;
  - Overlay replaces;
  - the menu's Add 3rd above.
- `mix precommit`, then a browser check by the user.
