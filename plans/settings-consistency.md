# Settings never contradict each other

## Context
Standing rule (memory `settings-never-conflict`): no combination of settings the user governs
may contradict another. When one setting fixes another, the UI locks or limits it, and the
server validates it too. This audit covers every setting: score settings (editor dialog and New
composition), and the tempo-change dialog.

Already consistent:
- Time signature and its symbol: common time locks 4/4, cut time locks 2/2, and other times
  offer only numbers (the `time-symbol-row` change).
- Key and mode are independent of everything else.
- The playback instrument is a listening choice, separate from the version's instrument.

## Conflicts found

| # | Settings | Contradiction today | Fix |
|---|---|---|---|
| 1 | Pickup beats ↔ time signature | The field accepts any number. A pickup of a whole bar or more is refused only after Apply | The field's max follows the time: beats per bar − 1. Changing the time keeps it in range |
| 2 | Gradual tempo change: start ↔ end BPM | "Gradually" with the same start and end tempo is accepted and labelled "accel.", though nothing changes | A gradual change needs a different end tempo. It is rit. when the end is slower and accel. when faster, and the dialog shows which |
| 3 | Gradual change length ↔ the next tempo change | "Over 16 beats" is accepted with another change 4 beats later. The next change silently cuts it short, and it is clipped silently at the end of the score | "Over (beats)" is limited to the room before the next change, or the end of the score, and the dialog shows that limit |
| 4 | Starting tempo ↔ a tempo change at the very start | A change can be placed on beat 1 of bar 1, so the score has two opening tempos (settings say 100, the change says 80) | **Decision needed** |
| 5 | Tempo marking ↔ starting BPM | "Largo" at 200 BPM, or "Presto" at 40, is accepted | **Decision needed** |

## Decisions (2026-11-10)
- **#4: the settings are the starting point.** The score's opening tempo is the settings'
  starting tempo, so a tempo change can't be placed on the opening beat (tick 0):
  - the right-click "Tempo change" on the first note isn't offered;
  - a drag that would move a change there stops at the next beat;
  - the server refuses it (`TempoEditing.put`).
  The opening tempo is changed in Score settings.
- **#5: a marking suggests a BPM.** Choosing a marking (in Score settings or New composition)
  sets the starting BPM to that marking's usual tempo, from one documented table in
  `TempoMarking` (`suggested_bpm/1`). The BPM can then be set to anything. Changing only the BPM
  leaves the marking alone.

## PRs (after the queued ones: band fix, test timeout, tempo markings, time symbol row)
1. Pickup max (#1): settings fields + `SettingsDialog`/New composition test.
2. Tempo-change dialog (#2, #3): `TempoForm.validate` gets the next change's tick and the end of
   the score. The dialog limits the beats and needs a different end tempo.
3. No tempo change on the opening beat (#4): `TempoEditing` refuses it, and the menu and drag
   respect it.
4. Marking suggests BPM (#5): a `TempoMarking` BPM table + the settings forms' change handlers.
Each follows the standing rule: the UI locks or limits the setting, and the server validates
it too.
