# Hands on their own staves

Follows the moving-notes PR (#30), whose rule moved a note to the other staff
as soon as it passed middle C. A left-hand part often reaches a few ledger
lines above middle C on the bass staff, and a right-hand part below it on the
treble, so that rule was too strict. Agreed: options 1 and 2 together.

## 1. A note crosses at the middle of the gap, not at middle C
- The gap between the staves is 8 staff spaces (`Staff`). Its middle is
  4 spaces (8 steps) from each staff:
  - the treble staff keeps notes down to **D3** (step 22);
  - the bass staff keeps notes up to **B4** (step 34);
  - each on its fourth ledger line into the gap.
- A note moved past that (↑/↓ by step, Shift octave, Ctrl semitone, or
  dragged) moves to the other staff, as before: same time, length, dots and
  pitch; it joins a same-length note there as a chord, else another voice.
- `StaffCrossing.staff_for/2` holds the limits; a test checks they are the
  steps at the middle of the engraved gap.
- The drag preview splits the gap at the same line (`geometry.js`:
  `staffFor/3`, `staffStepAt/3`, no clamping at middle C), so a dragged note
  lands where it is shown.

## 2. Put on the treble staff / Put on the bass staff
- Right-click items for a note and for a selection. The notes move to that
  staff at their own pitch, however far from it (`Editing.put_on_staff/4`,
  `StaffCrossing.restaff_all/3`, `EditorCommands.menu("put_on_staff", …)`).
- A note put far outside its staff's half of the gap goes back on its next
  move, by rule 1.

## Tests
- `moving_notes_test.exs`: the limits, a left-hand G3 staying on the bass
  staff up to B4 and crossing past it, a right-hand note staying down to D3,
  octaves, chords, and Put on staff (chord, voice, far away, duplicate).
- `note_menu_test.exs`: the menu item reports an edit that moves the notes.

## Browser check
- A bass note moved up with ↑ past middle C stays on the bass staff (with
  ledger lines and a normal stem) until past B4.
- Dragging into the gap: the note lands on the staff whose half it was let go in.
- Right-click › Put on the treble / bass staff, for one note and a selection.
