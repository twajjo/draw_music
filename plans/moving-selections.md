# Moving a selection with ← and → (whole, never split)

Agreed 2026-11-18. Replaces the beat moves of ←/→ and the rest swap of #78.

## The rule

A selection moved with ← or → moves **whole**: no selected note or rest is
ever split, and none is ever tied over a bar line by the move. The music it
passes over (whole items, never parts of one) moves the other way, to fill
the place it left. Notes and rests are treated alike.

1. **One step:** the selection trades places with the item(s) beside it,
   on the staves (and voices) it covers: → passes the items that start
   where it ends; ← the items that end where it starts.
2. **Never split:** if that would leave a selected item across a bar line,
   it passes more whole items until it lands wholly inside one bar: it
   jumps the bar line whole, and an equal length of music moves back.
3. **Rests follow the convention:** a selected rest may only land where the
   rest-writing rules allow it (in 4/4 a half rest on beat 1 or 3, never on
   beats 2–3; a dotted rest only where the meter allows one). If the next
   step would put it somewhere else, it passes more items until it lands
   on an allowed place. Notes may land anywhere in a bar (syncopation is
   fine).
4. **What moves the other way** is not selected: it may be split and tied
   over a bar line like any other music, and its rests are rewritten.
5. **Afterwards:** every bar touched is rewritten (filler rests whole, on
   the beats); the moved items stay selected; one moved item puts the
   cursor just after it (as selecting one does). At the start or end of the score nothing moves (→ at the end does
   not add bars).
6. **One undo step** per press.

### The worked example (4/4, treble)

| Press → | Bar 1 | Bar 2 |
|---|---|---|
| Start | C, quarter rest, **half rest** | quarter rest, G, C, quarter rest |
| 1 | C, quarter rest, quarter rest, G | **half rest**, C, quarter rest |
| 2 | (unchanged) | C, quarter rest, **half rest** (beats 2–3 aren't allowed, so it passes both) |
| 3 | (unchanged) | C, quarter rest, then bar 3's first half; the **half rest** jumps whole into bar 3 |

### Decided

- **The selection is the selection** (2026-11-18): a moved rest keeps its
  own value and stays selected; it is not merged into the silence beside
  it (a moved half rest stays a half rest), as a rest the user placed is
  kept. Only the music passed over, and the gaps, are rewritten.
- **Selections spanning several staves or voices** move as one block: the
  passed music is whole items on every staff the selection touches.
- **↑/↓ are unchanged** (pitch).

## Pull requests

1. **Rest writing follows the rules** (`DrawMusic.Music.Gaps`). Checked
   per meter: simple meters (4/4, 3/4, 2/4, 2/2) were already right (a
   half rest only on beat 1 or 3; an empty bar one rest, drawn whole).
   - **1a (done):** compound meters (6/8, 9/8, 12/8) rest a dotted beat at
     a time: a dotted quarter rest per silent beat, a dotted half for two
     beats from beat 1 or 3, and inside a beat plain rests that don't
     cross into the next. They used to come out as an eighth and a quarter,
     or a quarter straddling beat 2.
   - **1b:** an empty bar no single rest fills (5/4, 9/8) is still two
     rests; it should be drawn as one whole-bar rest. That is the
     engraver's (`Engraving.Notes`, already 507 lines: split it first).
     - **1b-split (done, #81):** the rest drawing moves out of
       `Engraving.Notes` into `Engraving.Rests` (Notes 404 lines, Rests
       122); `voice_counts/1` moves to `Music.Measure`. No behaviour change.
     - **1b (done, #82):** a silent bar (no notes, only filler rests, one
       voice: `Fillers.silent_bar?/2`) is drawn as one whole-bar rest,
       hit-tested where it's drawn; a click selects all its rests and puts
       the cursor after the bar. Rests the user placed are drawn as written.
   Step 3 above leans on these rules.
2. **Moving a selection whole** (replaces #78, closed; done): `Editing.Time.step/4`
   (the block move with displacement, rules 1–6), the arrow wiring, the
   cheat sheet's ←/→ entry. Tests: the worked example, a note jumping a
   bar line, a chord, a selection on both staves, the ends of the score.
3. **Documentation:** the cheat sheet says it in PR 2; the user guide's
   topic list (draw-music-plan.md, Phase 12) gets "Moving a selection: it
   moves whole with ← and →, never split; the music it passes moves back;
   rests land only where the rules allow" (added with this plan).
