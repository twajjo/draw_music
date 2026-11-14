# Moving notes: their accidental, and crossing middle C to the other staff

A behaviour PR after 11a (found while checking 11a in the browser; the
behaviour is older than 11a).

## What's wrong today
- A dragged note (to another step, or to the other staff) loses the
  accidental it had: `Editing.move_steps` and `restaff/5` give it the key's
  version of its new letter.
- ↑/↓ (and dragging several notes together) never moves a note to the other
  staff. A bass note moved high above the treble staff is still a bass note:
  - it is drawn with the bass staff's ledger lines, its stem reaching down to
    the bass staff's middle line;
  - the bass staff's rests are counted around it, and the treble staff
    keeps its whole rest;
  - a note inserted "after it" on the treble staff goes to the treble
    staff's beat 1, under its stem, since the treble staff is empty.

## Decisions (agreed)
1. **A moved note keeps its accidental** wherever it lands. Shift (sharp) or
   Ctrl/Alt (flat) during a drag still sets one. (F♯ up a step → G♯.)
2. **Middle C is the boundary between the staves.** A bass note moved above
   middle C (D4 and up) moves to the treble staff; a treble note moved below
   it (B3 and down) moves to the bass staff; middle C stays on whichever
   staff the note is on. This applies to ↑/↓, to dragging several notes, and
   to dragging one note.
3. **On the new staff:** the note keeps its time, length, dots and
   accidental. The old staff gets that time back as rests, and the new
   staff's rests make room for it.
4. **If the new staff already has a note at that time:** the moved note
   joins it as a chord when their lengths match, else it goes into another
   voice.

## Tests to include
- F♯ dragged up a step lands as G♯; with Ctrl held, as G♭.
- A bass dotted quarter moved up with ↑ past middle C becomes a treble note:
  the bass measure becomes a whole rest, and the treble measure the dotted
  quarter plus rests.
- Then a quarter inserted after it on the treble staff lands on beat 2½,
  followed by rests.
- A note crossing to a staff with a same-length note at that time joins it
  as a chord; a different length gives another voice.
- Middle C itself doesn't change staff.

## As built (2026-11-13)
- "Keeps its accidental" is measured against the key: a moved note is the
  key's version of its new letter, sharpened or flattened as much as it was
  from the key's version of its old one. F♯ in C major goes up to G♯, but the
  key's own F♯ in G major goes up to G, not G♯.
- `DrawMusic.Music.StaffCrossing` (new, pure, on timeline entries) holds the
  middle-C rule and the move to the other staff (join a chord, else the
  lowest free voice, rests under it give way). `Editing.move_steps`,
  `transpose_chromatic`, `transpose_interval` (↑/↓ with Shift or Ctrl) and
  `move_to_staff` (a single dragged note) all use it. `editing.ex` stays
  about the same size.
- A note keeps its id when it changes staff (it used to get a new one).
- The drag preview shows and sounds the kept accidental: noteheads carry
  `data-alter` (`Glyph.alter`). The preview still draws on the dragged
  note's own staff; the note lands across middle C when let go.

## Files (expected)
`music/editing.ex` (`move_steps`, `restaff`, the crossing rule),
`editor_commands.ex` (if the drop commands change), `shortcuts.ex` (`/help`:
moving keeps accidentals, crossing middle C), tests.
