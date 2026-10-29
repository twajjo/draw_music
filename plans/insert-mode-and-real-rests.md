# Insert mode follows notation rules; every rest is real (2026-10-25)

## Context
While checking the uncommitted batch in the browser, the user found these problems:
- Rests drawn in the gaps can't be selected. They are drawn from `Gaps.rests/2` but never stored, so they have `id: nil`.
- Insert mode places an item exactly where you click, which can leave a gap in front of it.
- When an insert pushes a note across a bar line, the note is split into tied pieces. If later edits bring it back inside one bar, the pieces are never merged again.
- While a palette item is armed, a click on an existing note places another item instead of selecting the note.

## Rules agreed with the user
1. **Every rest is a real, stored item.** It can be selected, deleted, re-lengthened or turned into a note, just like a note.
2. **Insert never leaves a gap.** A click past the staff's last note places the new item right after that note. In an empty bar it goes on beat 1. Overlay still places exactly where you click.
3. **Insert pushes everything after the insertion point** right, through the end of the piece. Editing a single measure may come later.
4. **Only trailing rests shrink.** Rests after the last note of the whole piece absorb the push. Rests between notes move with the music. Example: a final bar of H + H‑rest, with Q inserted in front, becomes Q H Q‑rest.
5. **Re-spell.**
   - Filler rests are rewritten on the beats after every edit.
   - Tied pieces of a lone note merge back into one note only in edits that move music in time: Insert placing and lengthening, Insert delete, shift, paste, and time-signature change. Split and hand-drawn ties survive all other edits (user decision).
6. **A click on an existing note or rest selects it,** even while something is armed. A click on empty staff places the armed item. There's no Alt+click, because Alt already means "flat". To stack a chord, click another line or space at the note's start.
7. **An Insert item too long for the rest of the bar is tied over the bar line** (`Placement.cross_bar`). It is not refused with "bar is full".

## How it's built
- `Rest.filler`: `Gaps` writes filler rests. `Editing.rebuild` drops filler and then refills it, keeping filler ids stable per measure.
- `Session.new`, `insert_measure/3` and `append_measure/2` also fill.
- An edited filler rest becomes the user's (`claim/1`).
- Insert landing: `Editing.insert_point/4`, used by `EditorPlacement.place/5`.
- Range selection takes in a filler rest only when the whole rest is inside the band.

## Assumption (not asked)
An insert shifts only the target staff, as it does today.

## Verification
- Run `mix precommit`.
- Browser check: repeat the screenshot sequence in Insert mode. Every rest must be clickable and deletable, and a click selects even while something is armed.
