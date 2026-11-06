# Review: `lib/draw_music/music/editing.ex` (from the Phase 5 code review)

Recorded 2026-11-04. The user made this **Phase 8 work**: do the full split, not the smaller alternative. It's built when Phase 8 starts.

## The problem
`Editing` was 1,346 lines at the Phase 5 review and is 1,404 now. It has 32 public functions (42 clauses) and 73 private ones (100 clauses). It holds every kind of edit: placing, pitch changes, time changes, values, chords, ties, measures, tempo shifting, selection, the clipboard, filler rests, and the validity check that every edit ends with. Public and private functions are interleaved, so the API is hard to see at a glance.

(`editor_live.ex`, at 1,424 lines, is over the same limit; it deserves its own review.)

## Redundant patterns
1. **Looking up entries by id is written five ways:**
   - `find_entry/2`;
   - `find_entries/2`;
   - `fetch/2` on a map from `note_entries/2`;
   - inline `Enum.filter(&(&1.event.id in ids))` in `reverse` and `copy`;
   - `Enum.split_with` in `delete`.

   `MapSet.new(ids)` is repeated 6 times, and `Timeline.flatten(score, ctx)` 22 times. One `Entries.select(entries, ids)` (returning `{chosen, rest}`) plus `find`/`find_all` would cover them.
2. **Building events from a placement or another event, four times:** `new_note/4`, the inline `%Rest{}` in `place_rest/4`, `rest_from/1` and `note_from/3` each copy staff, voice, offset, value and dots. `Note.from/2` and `Rest.from/1` constructors on the structs would replace them.
3. **Two "does it fit in the bar" checks:**
   - `locate` + `place_within` (by bar index and offset);
   - `fits_bar` + `within_bar` + `bar_of` (by absolute tick).

   `restaff` has a third inline bar search (`Enum.find_value` with an index). These belong together, probably in `Timeline` (`bar_at/2` returning the index and the bar, and `fits?/3`).
4. **Two definitions of "same chord":** `same_chord?/2` (staff, voice, start and ticks) and `chord_key/1` (staff, voice and start). They agree on any valid score, since same-start notes of different lengths in one voice are refused as `:overlap`. Keep one.
5. **Turning a boolean into `:ok | {:error, reason}`:** `dots_allowed/2`, `check_tieable/2`, `check_range/1`, and the `nil → {:error, :not_found}` shape of `find_entry`/`fetch`. A single `ensure(bool, reason)` helper would cover them.
6. **Accepting one id or a list:** `split`, `set_value` and `to_rest` each have a clause that wraps a single id into a list. Callers could pass lists (or use `List.wrap`), which removes three clauses and makes the specs plain `[id()]`.
7. **Repeated small expressions:**
   - `Pitch.key_alter(ctx.sf, Pitch.letter(step))` appears 3 times, which suggests a `Pitch.in_key(step, sf)`;
   - `entry.start + entry.ticks` appears 12 times, which suggests a `Entry.end_tick/1` in `Timeline`.
8. **Dead or nearly dead API:**
   - `append_measure/1` is not called anywhere;
   - `insert_measure/2` is only called by `insert_measure/3`.

   Both could become private, or `insert_measure/2` could fold into `/3`.
9. **The result shape `with {:ok, score} <- …, do: {:ok, score, id}`** repeats in about 8 functions. It's fine as is; it becomes less noisy once the modules are smaller.

## Suggested split
The pure helpers move first, then the edit groups. The public API is kept stable with `defdelegate` in `Editing`, so `EditorCommands`, `EditorLive`, `Session`, `MidiCodec` and the tests don't change at first. Callers can move to the submodules later if wanted.

| New module | Takes | Est. lines |
|---|---|---|
| `Music.Spans` (pure interval math) | `merge_spans`, `cut_out`, `cursor`, `overlapping_in_voice?`, `span`; the "clear the time" part of `clear_span` | ~70 |
| `Music.Ties` | `tie`, `untie`, `tieable?`, `prune_ties`, `merge_ties` (+ `mergeable`, `extend`), `put_tie`, `drop_outside_tie`, `renumber`, `flipped` | ~170 |
| `Music.Fillers` | `fill_rests`, `refill`, `filler_ids`, `filler_key`, `filler?`, `claim` | ~60 |
| `Music.Editing.Rebuild` (the shared core every edit ends with) | `rebuild`, `add`, `clear_rests_under`, `check_layout`, `check_voice`, `collision`, `check_range`, `map_selected`/`map_entries`, the entry lookups | ~150 |
| `Music.Editing.Place` | `place_note`, `place_chord`, `place_rest`, the voice search, the duplicate check, `locate` | ~180 |
| `Music.Editing.Pitches` | `set_alter`, `move_steps`, `move_to_staff`, `transpose_chromatic`, `transpose_interval` | ~110 |
| `Music.Editing.Time` | `shift`, `insert_time`, `insert_point`, `delete`, `reverse`, `rebar_to` | ~200 |
| `Music.Editing.Values` | `set_dots`, `set_value`, `split` (+ `halves`), `to_rest`, `to_note` | ~170 |
| `Music.Editing.Chords` | `chord_ids`, `add_to_chord`, `chordify` | ~100 |
| `Music.Editing.Measures` | `insert_measure`, `append_measure`, `delete_measure` | ~70 |
| `TempoChange` (or a new `Music.Tempos`) | `shift_tempos`, `shift_field`, `keep_ramp_forward`, the ramp clamp in `delete_measure` | ~50 |
| `Clipboard` (existing) | `copy`, `paste`; `select_range` goes to `Time` or `Timeline` | ~70 |
| `Editing` (facade) | the moduledoc (the invariants), `reason`/`result`/`id` types, `defdelegate`s | ~80 |

Every module is then well under 500 lines. The invariants stay documented in one place (`Editing`'s moduledoc), and each submodule points back to it.

**Alternative (smaller step):** extract only the pure helpers (`Spans`, `Ties`, `Fillers`, `Rebuild`) and fix redundancies 1–8. That brings `Editing` to roughly 700 lines, all of them edit operations, and defers the per-area split.

## Ordering (new rule)
Within each module, public functions come first and the `defp`s are grouped together at the bottom. Today they're interleaved by topic. That applies to `editing.ex`, or to each new module if it's split. 25 other non-generated modules in `lib` also interleave them, so they're part of the same Phase 8 sweep.

## Risk and verification
- The behaviour must not change. `editing_test.exs` and the editor LiveView tests cover the edits, and `mix precommit` must stay clean after each step.
- Do it as separate jj changes: helpers out, redundancies fixed, then the split. That way each step's diff is reviewable.
