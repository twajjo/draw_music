# Suggest a key

Notes entered by ear into a piece left in C major (or any key) can gather
many accidentals, a sign the music is really in another key. The editor
suggests better keys and re-keys the piece without changing how it sounds.

## What the user sees
- A **Suggest key** button on the palette's second line, between the
  Insert/Overlay toggle and the Settings gear.
- It is **enabled only when the current key fits badly**: the notes carry
  many accidentals for the current key (any key, not just C major) and some
  other key would write clearly fewer. Otherwise it is disabled, with a
  title saying why.
- Pressed, it opens a **drop list of keys in descending order of fit**,
  each with the accidentals it would leave, e.g. "E♭ major: 5 accidentals
  (now 41)". The best fit is the key leaving the fewest accidentals (the
  user's call, after trying it); `KeyDetection`'s correlation only breaks
  ties, e.g. between a major key and its relative minor, which share a
  signature and are both listed.
- The whole piece is judged, whatever is selected.
- Choosing one **re-keys** the piece: new key signature, same sounds. Each
  note is re-spelled for the new key (`Pitch.spell/2`): an A♯ entered in C
  becomes B♭ in E♭ major. Rhythm, ties, voices and staves stay. It is one
  undoable step.
- Saving follows the Key setting's rule: a saved version re-keyed is saved as
  a new version in the new key; the unsaved draft just changes.

## How the fit is judged
- `KeyDetection` ranks the 24 keys by how long each pitch class sounds
  (Krumhansl–Schmuckler); a new `ranked/1` returns them all, best first
  (`detect/1` stays for MIDI import).
- Accidentals are counted as engraved (`Accidentals.displayed/3`) in the
  current key and as they would be after re-keying.
- "Many": enabled when the best key writes at least 2 fewer accidentals
  than the current key and at most half as many. (First set at 6 fewer,
  which a 3-bar piece with 4 accidentals, "Cow Town", could never reach.)
- One key per piece: music that changes key gets the best single key.

## PRs
1. **K1: re-key in place.** `DrawMusic.Music.Rekey` (respell every note for
   a new key, keep ties), `KeyDetection.ranked/1`, the accidental count and
   suggestions (`DrawMusic.Music.KeySuggestion`: the ranked keys with their
   accidental counts, and whether to suggest at all), with tests.
2. **K2: the palette button.** The Suggest key button and its drop list
   (a component owning its open/close; the choice goes to the editor as
   `{:rekey, {sf, mode}}`), the editor's handling (session context change,
   saving in the new key), `/help`, tests.
