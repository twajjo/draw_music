# Locked measures: keep time-shifting edits inside chosen measures

Asked for on 2026-11-14 while reviewing the staff work.

## What happens today
In **Insert** mode, edits that take or give back time move all the later
music on that staff, to the end of the piece:
- placing a note or rest pushes everything after it on that staff later
  (`EditorPlacement.make_room` → `Editing.insert_time`), adding measures at
  the end if needed;
- lengthening a note or rest (a longer value, or a dot, from the palette or the
  right-click menu) pushes the later music later the same way;
- deleting pulls everything after it on that staff earlier (`Editing.delete`).

In **Overlay** mode nothing moves: a placement types over what's there, and a
deletion leaves rests. So today the choice is "the whole rest of the staff
moves" or "nothing moves".

## What's wanted
A **lock** beside each measure's **+** and **−** buttons. Locked measures form
one run of neighbouring measures (one or more). While measures are locked,
the time-shifting edits move music only within them, so the rest of the
piece stays exactly where it is.

## Proposed behaviour (to confirm, see the questions)
- **Choosing:**
  - clicking a measure's lock locks it;
  - clicking the lock of a measure next to the run adds it to the run;
  - clicking a lock elsewhere starts a new run there;
  - clicking a locked measure's lock unlocks it, but only at either end of
    the run, so the run stays one piece;
  - an "Unlock all" control appears while any measure is locked.
- **Inside the run (Insert mode):**
  - **placing or lengthening** pushes the later music within the run later.
    Music pushed past the run's last barline is refused ("Not enough room in
    the locked measures"), and the edit doesn't happen;
  - **deleting or shortening** pulls the later music within the run earlier,
    and the time freed at the run's end becomes rests. Music after the run
    doesn't move.
- **Outside the run:** edits work as today. Alternatively, they're refused
  while a run is locked; see question 3.
- **Drawing:** locked measures are tinted, with a closed lock, so the run is
  clear. Their + and − stay available.
- **Overlay mode** is unchanged: it never moves anything anyway.
- **After the run's last item:** the space after a bar's last note or rest
  belongs to the next bar (like a text cursor, both modes act on what is to
  its right). After the run's last bar there is no next bar to affect, so a
  click there is refused with a message, in Insert and Overlay alike.

## Decided (2026-11-14)
- **The lock belongs to the editing session only.** It isn't saved with the
  version, and it's gone when the editor is closed.
- **Edits in other measures work as today** while a run is locked.
- **Staves follow today's shifting rules.** Today an edit shifts only the
  staff being edited, so inside a locked run only that staff's music moves,
  and only within the run. The other staff never moves, as now.

- **When an edit inside the run needs more room than the run has**, either
  behaviour can be chosen, **by right-clicking a lock** (a small menu on the
  locked run):
  - **Refuse** (the default): the edit doesn't happen, with a message ("Not
    enough room in the locked measures");
  - **Drop the overflow**: the music pushed past the run's last barline is
    removed (cut at the barline if it straddles it), and the run's end is
    filled.

  Like the lock itself, the choice lasts for the editing session only. The
  same menu also offers "Unlock all".

## How it would be built (outline)
- The run as editor state: `{first, last}` measure indexes, or none. Held by
  the editor (later, `Editor.ScoreCanvas`).
- `Editing.insert_time` and `Editing.delete` (and the lengthening in
  `EditorCommands`) take an optional window `{from_tick, to_tick}`. Inside it,
  they shift only the entries in the window, and refuse with `:locked_full` if
  anything would cross its end.
- The measure controls (`EditorComponents.measure_controls`) get the lock
  button and the tint; `/help` gets the lock.
- Tests: rippling stays inside the run, a full run refuses, music after the run
  doesn't move, and choosing keeps the run one piece.

## When
After the open staff and reading-aids work, and before or after 11b/11c, as
you prefer. 11b moves the measure controls into `Editor.ScoreCanvas`, so
doing locks after 11b avoids building them twice.
