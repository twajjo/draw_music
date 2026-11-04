# Phase 5 fix: click selects, drag moves (2026-10-24)

## Context
Manual testing turned up these problems:
- Clicking a note picks it up, so there is no plain click-to-select.
- A dragged note never changes staff. Dropped in the bass, it stays a treble note with a ladder of ledger lines.
- While dragging, only the notehead moves; its stem, ledger lines and accidental stay behind.
- Gaps on a staff that has notes show no rests.
- Bass tones are inaudible on small speakers, because the placement beep is a pure triangle wave.

## Decisions (user, 2026-10-24)
- **Click and drag:**
  - a click on a note or rest selects it (Shift toggles) and doesn't move it;
  - dragging a note moves it, sounding each new line or space, and it lands on mouse up;
  - dragging a selected note moves the whole selection;
  - Esc or a right-click cancels the drag.
- **Placing from the palette:**
  - hovering shows the ghost silently;
  - pressing sounds it, dragging sounds each new line or space, and releasing places it.
- **Changing staff:** a single note dragged onto the other staff moves to that staff. With several notes, each stays on its own staff.
- **Sound:** drag and placement tones play through the loaded instrument. The synth fallback gets a fuller waveform.

## Changes
- **Engraving:**
  - `Glyph` gets `staff`, set for noteheads, rendered as `data-staff`, so the hook knows a note's staff and step;
  - `Notes.rests` draws implied rests (id nil, not selectable) in the gaps of each voice that has notes, using gap logic shared with `Editing.fill_rests`.
- **Editing:** `move_to_staff(score, ctx, id, staff, step)` removes the note and places it on the other staff at the same time, value and dots, in the lowest voice it fits.
- **EditorLive `drop`:**
  - takes an optional `staff` for a single id;
  - the moved notes end up selected.
- **Hook (`index.js`):**
  - a pending press turns into a drag past the threshold, or into a select on release;
  - the drag preview is drawn in the overlay (head, ledger lines, accidental) while the original head fades;
  - the pick-up and second-click drop go away;
  - placing happens on pointerup.
- **`audio.js`:** a `preview(midis)` that sounds through the current player. The hook's own Tone synth goes away.
- **Cheat-sheet:**
  - click, drag and place entries updated;
  - the "pick up" wording goes.

## Verification
- **Unit tests:**
  - `move_to_staff`, including that the old staff has a gap and the new staff has the note;
  - implied gap rests are engraved;
  - `drop` with a staff.
- `mix precommit` is clean.
- **Manual:**
  - a click selects, then Delete removes it;
  - dragging sounds each step and lands on release;
  - a treble note dragged into the bass sits in the bass with rests around it;
  - no stray ledger lines while dragging;
  - bass notes are audible.
