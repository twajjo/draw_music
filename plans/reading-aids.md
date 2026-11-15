# Reading aids: the editor for novice and proficient readers

The editor should suit both someone who reads music fluently and someone who
is still learning to. A proficient reader sees a clean score; a novice can
turn on aids that name the notes. Asked for while checking the moving-notes PR
(#30): the gap between the staves looks like room for many notes, but only
middle C and a ledger line or two on each side lie there, so a dragged note
seems to "jump" when let go.

## Settings vs preferences (agreed)
- **Settings** belong to the piece: the Score settings dialog (key, time,
  tempo, instrument, …).
- **Preferences** belong to the user: the page reached from the account
  menu. That menu's "Settings" becomes **"Preferences"**, and so does the
  page's heading. The route and the generated auth code stay as they are; the
  ink and layout choices already kept there are preferences.
- The reading aids are preferences: each user turns them on or off for
  themselves.

Three small PRs, each merged before the next.

## R1: "Name the note" preference, and a preview that never jumps
- **The account menu's "Settings" becomes "Preferences"**, and so does the
  page's heading.
- **A new preference, "Name the note being placed or dragged"** (on or off,
  **on** by default), on the Preferences page. Stored on the user, like the
  layout; the editor passes it to the score hook as a data attribute.
- **When on**, a small label names the note on the ghost: its letter and
  accidental, no octave ("G♯"). A natural shows ("F♮") only when the note
  would otherwise read sharp or flat, by the key or an earlier accidental
  in the measure (as `Accidentals`). Labels appear:
  - while hovering with a note armed;
  - while pressing to place;
  - while dragging. With several notes dragged, the one under the pointer is
    named.

  Chords keep their chord name, as now.
- **The preview follows the middle-C rule** (always, not a preference). In
  the gap between the staves, the treble side stops at middle C and so does
  the bass side. The ghost then always shows where the note will land, on
  its real staff.
- Files: migration (`users.name_notes`), `Accounts.User` (changeset),
  `UserLive.Settings` (the toggle, the heading), the layout's account menu,
  `EditorLive` (data attribute), `geometry.js` (`staffStepAt`), `overlay.js`
  (the label), `note_drag.js`, `index.js`, a small pure `note_name.js`,
  `/help`, and tests.

## R2: two more preferences, both **off** by default
Two separate preferences on the Preferences page, each on or off on its own.
Built as two PRs: **R2a**, the staff letters (drawn by `ReadingAids` as
`ReadingAid` labels in the editor's pieces, in a margin widened from 1 to 3
staff spaces; the export has its own margins and never gets them), and
note names in two more PRs (changed after review: names belong to the
existing "name notes" preference, with a second toggle for when they show):
- **R2b**, selected notes named: with "name notes" on, each selected note
  (one, a chord or a range) is named beside its head, whether just selected
  or moved with ↑/↓. The server draws them (`ReadingAid` `shown:
  :when_selected`, drawn only while the note is selected), so the arrow
  keys' JS labels went; ♮ follows the engraving's written `sign`.
- **R2c**, when the names appear: a second toggle under "name notes",
  "While editing and placing" or "At all times" (`users.name_notes_always`),
  locked while "name notes" is off. At all times, every note is named.
- **"Letter the staff lines and spaces"**: tiny letters at the start of each
  line of music:
  - each staff's spaces (treble F A C E, bass A C E G);
  - its lines (treble E G B D F, bass G B D F A);
  - middle C marked between the staves.
- **What it isn't part of:** the downloaded SVG, the MIDI or the score itself.
  It's a way of viewing, not part of the music.
- Files: migrations (`users.letter_staves`, `users.name_notes_always`),
  `Accounts.User`, the Preferences page, the engraving or `ScoreSvg` (the
  letters, drawn only in the editor), `/help`, tests.

## R3: a music cheat sheet (concepts, not the application), in the user-guide phase
Written with the user guide (the last phase), and **linked from the editor's
`/help` cheat-sheet**. Music basics for novices, with small drawn examples:
- the staff, clefs, and the grand staff;
- middle C and ledger lines;
- note names on lines and spaces (Every Good Boy Does Fine, FACE, Good Boys
  Do Fine Always, All Cows Eat Grass);
- sharps, flats and naturals, and how an accidental lasts to the end of its
  measure;
- key signatures;
- note and rest values, dots and ties;
- time signatures and measures;
- chords: a quality on any root (C major, A major's C♯) vs the key's own
  scale-degree chords (I, ii, iii, IV, V, vi, vii°);
- tempo markings, rit. and accel.

## Exports stay standard notation (a firm rule)
None of the reading aids ever appears in exported sheet music. The SVG
download (and the MIDI) is standard, compliant notation, whatever the user's
preferences:
- The R1 label is drawn by the browser on the editor's overlay, which is never
  part of the score's SVG.
- R2's letters are drawn only for the editor's own view, as a separate layer
  the export path never builds. The export renders the score with no
  preferences passed at all.
- R2 gets a test: with both letter preferences on, the downloaded SVG has no
  letter elements and matches the export with them off.

## Decided
- "Name the note being placed or dragged": on by default.
- Staff letters (FACE / ACEG …) and names beside every note: two separate
  preferences, both off by default.
