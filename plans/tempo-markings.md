# Tempo marking: a drop list of known markings

## Context
The score settings' "Tempo marking" is a free text field, so anything can be typed. Markings
are an established vocabulary, so the field becomes a drop list of known markings, grouped by
language. "None" stays allowed. Nothing outside the list can be entered.

## Where a marking comes from today
- The settings form, `LibraryComponents.score_settings_fields/1`, shared by the editor's
  `SettingsDialog` and `NewCompositionLive`.
- Re-importing a .mid file this app exported: `MidiCodec` round-trips `tempo_text` in its own
  signature chunk. Other MIDI files never set it.

## Design
- **`DrawMusic.Music.TempoMarking`** (new) holds the list as data, grouped by language and
  ordered slow to fast within each group. It provides `groups/0` (select options) and
  `known?/1`.
- **Settings fields:** the text input becomes `<.input type="select">` with
  `prompt="None"` and the groups as optgroups.
- **Validation:** `Version.changeset` gets `validate_inclusion(:tempo_text, TempoMarking.all())`.
  Ecto runs it only when the marking *changes*, so:
  - a version already stored with an unlisted marking still saves untouched;
  - a new or changed marking must come from the list, including one from a re-imported .mid.
    A bad one is refused with the usual import error.
- **An unlisted marking already stored** shows in the drop list as its current value, labelled
  "(not in the list)", until it's changed. It can't be chosen again once changed.
- **/help:** no new keys or mouse actions, so the cheat sheet is unchanged.

## Proposed list (please review)
- **Italian:**
  - Larghissimo, Grave, Largo, Lento, Larghetto, Adagio, Adagietto, Andante, Andantino,
    Moderato, Allegretto, Allegro moderato, Allegro, Vivace, Vivacissimo, Allegrissimo, Presto,
    Prestissimo
  - Qualified forms: Lento assai, Adagio molto, Adagio ma non troppo, Andante cantabile,
    Andante con moto, Allegro ma non troppo, Allegro giusto, Allegro con brio,
    Allegro con fuoco, Allegro vivace, Allegro assai, Allegro molto, Presto agitato,
    Tempo giusto, Tempo di minuetto, Tempo di valse, Tempo di marcia
- **German:** Sehr langsam, Langsam, Ruhig, Mäßig, Mäßig bewegt, Bewegt, Lebhaft,
  Sehr lebhaft, Rasch, Schnell, Sehr schnell
- **French:** Très lent, Lent, Modéré, Assez vif, Animé, Vif, Très vif, Vite, Très vite
- **English** (popular and jazz sheet music; optional): Slowly, Moderately slow, Moderately,
  Moderately fast, Briskly, Fast

## PR
One PR (about 6 files): `TempoMarking` + its test, `score_settings_fields`, `Version` changeset
+ a changeset test, and the settings dialog test (choose from the list; an unlisted value is
refused). Opened after the band fix PR is merged.

## Verification
- `mix precommit`.
- In the browser: Score settings → Tempo marking lists the groups; choosing one shows it over
  the score; New composition has the same list.
