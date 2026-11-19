# Overlay placement zones

Agreed 2026-11-18. Replaces Overlay's snapping to the undotted value's grid
(a dotted quarter in 12/8 could not land on beat 4).

**Insert** stays like typing text: the new item goes in front of the item
clicked, and later music scoots right. No zones.

**Overlay** shows where the armed note or rest can land:

- **Zones:** while the pointer is over a bar, that bar is divided into
  vertical zones, one per place the armed item can start, **alternately
  shaded and unshaded** (like the alternating lines of a report).
- **How wide:**
  - shorter than a beat: zones of the item's own length, inside each beat
    (an eighth: 12 zones in 12/8, 8 in 4/4); a value that doesn't divide
    the beat evenly (a quarter in 6/8) gets zones on the meter's pulse
    (the eighth);
  - a beat or longer: one zone per beat (a dotted quarter in 12/8: 4; a
    half or a dotted quarter in 4/4: 4, so a half can start on beat 2).
- **Hover:** the zone under the pointer is highlighted over the whole
  length the item will cover, so it shows what will be replaced; the
  ghost snaps into the zone.
- **Click:** the item replaces exactly that much music from the zone's
  start; longer notes under it are broken up, rests rewritten by the rules
  (`DrawMusic.Music.Gaps`); a note running past the bar line is tied into
  the next bar.

## Decided: no automatic dots (by convention)

A time signature sets how the bar is grouped into beats, not which note
values are allowed: in 12/8 the bar is 12 eighths, felt as 4 beats of a
dotted quarter. Plain and dotted values are both normal there (a quarter
then an eighth is the commonest 6/8 and 12/8 rhythm), so dots are neither
required nor implied, in either mode, and a note can be dotted after it is
placed. What convention does govern, the app takes care of: rests are
written by the beat (`Gaps`), eighths are beamed by the beat, and the
zones show the beats. To help the user see the beat:

- the palette marks the value that is **one beat** in the current meter
  (a quarter in 4/4, a dotted quarter in 6/8, 9/8, 12/8), with one key to
  arm it; part of the zones PR.

## PR

One PR: the zone geometry (pure JS, beside `placing.js`), the overlay
drawing, the snapping, the cheat sheet (with a diagram), tests of the
zone rule.
