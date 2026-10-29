# 128th and 256th notes (agreed 2026-10-29)

Keep 960 ticks a quarter: a 128th is 30 ticks and a 256th is 15. A 128th takes at most one dot (45 ticks). A 256th takes none, because 7.5 isn't a whole tick.

- **Duration:**
  - Add `:hundred_twenty_eighth` and `:two_hundred_fifty_sixth`, with 5 and 6 flags.
  - `max_dots/1` gives the dots each value allows, and `dots_allowed?/2` checks a value and dot count.
  - `decompose/1` first tries the values down to the 64th, so existing lengths split exactly as before. Only lengths that can't be written that way (15, 45, 75…) use the new values.
- **Note and Rest changesets:** dots are validated per value.
- **Editing:**
  - `set_dots` and `set_value` refuse dots a value can't take (`:unrepresentable`).
  - Splitting a 64th now gives two 128ths, and a 256th is the one value that can't be split.
- **Palette:**
  - 128th and 256th buttons on keys 8 and 9.
  - Arming a 256th clears the dot, and the dot button is disabled while it's armed.
  - A chord that changes to a value which can't take its dots loses them.
- **Engraving:**
  - 128th and 256th flags, rests and palette glyphs from Bravura. Stems lengthen for the extra flags, and beams reach 6 levels; both already work from the flag count.
- **The length menu** lists the new values.
- **Cheat-sheet:** "1–9", and the dot can't go on a 256th.
- **MIDI import:** stays quantized to 64ths. Finer quantizing would turn played-in timing noise into 128ths.
