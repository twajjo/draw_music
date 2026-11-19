defmodule DrawMusic.Music.Editing do
  @moduledoc """
  Edits to a score. Every operation returns `{:ok, score, ...}` or
  `{:error, reason}` and leaves a valid score:

    * each staff has up to four voices, which may overlap one another freely
      (e.g. a quarter in voice 1 against two eighths in voice 2);
    * within one voice, events never overlap, except notes that start
      together with the same length, which form a chord (no two on the same
      step);
    * every note is within A0–C8;
    * ties join a note to the same pitch starting exactly where it ends;
      edits that break a tie remove it;
    * every gap is filled with stored `filler` rests (see `fill_rests/2`), so
      every rest drawn has an id. Filler gives way to whatever is placed or
      pushed into it; rests the user placed are kept like notes.

  Edits that move music in time (`insert_time/5`, `delete/3`, `shift/4`,
  `paste/4`, `rebar_to/3`) also merge the tied pieces of a lone note back
  into one where they follow each other, so a note pushed across a bar line
  and back is one note again; a bar line still splits it.

  Error reasons: `:no_such_measure`, `:measure_full`, `:overlap`,
  `:duplicate`, `:out_of_range`, `:before_start`, `:not_found`,
  `:not_tieable`, `:last_measure`, `:unrepresentable`, `:pickup_bar`.

  This module is the front: each edit is done by the module for its kind,
  and every edit ends through `DrawMusic.Music.Editing.Rebuild`:

    * placing: `DrawMusic.Music.Editing.Place`;
    * pitches: `DrawMusic.Music.Editing.Pitches`;
    * lengths: `DrawMusic.Music.Editing.Values`;
    * time: `DrawMusic.Music.Editing.Time`;
    * chords: `DrawMusic.Music.Editing.ChordEdits`;
    * bars: `DrawMusic.Music.Editing.Measures`;
    * copy and paste: `DrawMusic.Music.Clipboard`;
    * ties: `DrawMusic.Music.Ties`;
    * filler rests: `DrawMusic.Music.Fillers`.
  """

  alias DrawMusic.Music.{Clipboard, Context, Duration, Fillers, Note, Placement, Score, Ties}
  alias DrawMusic.Music.Editing.{ChordEdits, Measures, Pitches, Place, Time, Values}

  @typedoc "Why an edit was refused (see the module doc)."
  @type reason ::
          :no_such_measure
          | :measure_full
          | :overlap
          | :duplicate
          | :out_of_range
          | :before_start
          | :not_found
          | :not_tieable
          | :last_measure
          | :unrepresentable
          | :pickup_bar

  @type result :: {:ok, Score.t()} | {:error, reason()}
  @type id :: Ecto.UUID.t()

  @doc "Adds a note to a chord (see `DrawMusic.Music.Editing.ChordEdits.add_to_chord/4`)."
  @spec add_to_chord(Score.t(), Context.t(), id(), integer()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  defdelegate add_to_chord(score, ctx, id, steps), to: ChordEdits

  @doc "Appends a bar (see `DrawMusic.Music.Editing.Measures.append_measure/2`)."
  @spec append_measure(Score.t(), Context.t()) :: result()
  defdelegate append_measure(score, ctx), to: Measures

  @doc "A chord's ids (see `DrawMusic.Music.Editing.ChordEdits.chord_ids/3`)."
  @spec chord_ids(Score.t(), Context.t(), id()) :: [id()]
  defdelegate chord_ids(score, ctx, id), to: ChordEdits

  @doc "Turns notes into chords (see `DrawMusic.Music.Editing.ChordEdits.chordify/4`)."
  @spec chordify(Score.t(), Context.t(), [id()], ChordEdits.pitches_for()) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  defdelegate chordify(score, ctx, ids, pitches_for), to: ChordEdits

  @doc "Clears time for overwriting (see `DrawMusic.Music.Editing.Time.clear_time/5`)."
  @spec clear_time(Score.t(), Context.t(), non_neg_integer(), non_neg_integer(), [Note.staff()]) ::
          result()
  defdelegate clear_time(score, ctx, from, to, staves), to: Time

  @doc "Copies events (see `DrawMusic.Music.Clipboard.copy/3`)."
  @spec copy(Score.t(), Context.t(), [id()]) :: Clipboard.t()
  defdelegate copy(score, ctx, ids), to: Clipboard

  @doc "Deletes events, closing their gaps (see `DrawMusic.Music.Editing.Time.delete/3`)."
  @spec delete(Score.t(), Context.t(), [id()]) :: result()
  defdelegate delete(score, ctx, ids), to: Time

  @doc "Deletes a bar (see `DrawMusic.Music.Editing.Measures.delete_measure/3`)."
  @spec delete_measure(Score.t(), Context.t(), non_neg_integer()) :: result()
  defdelegate delete_measure(score, ctx, index), to: Measures

  @doc "Rewrites the filler rests (see `DrawMusic.Music.Fillers.fill/2`)."
  @spec fill_rests(Score.t(), Context.t()) :: Score.t()
  defdelegate fill_rests(score, ctx), to: Fillers, as: :fill

  @doc "Inserts a bar (see `DrawMusic.Music.Editing.Measures.insert_measure/3`)."
  @spec insert_measure(Score.t(), Context.t(), non_neg_integer()) :: result()
  defdelegate insert_measure(score, ctx, index), to: Measures

  @doc "Where an insert lands (see `DrawMusic.Music.Editing.Time.insert_point/4`)."
  @spec insert_point(Score.t(), Context.t(), Note.staff(), non_neg_integer()) ::
          non_neg_integer()
  defdelegate insert_point(score, ctx, staff, at), to: Time

  @doc "Inserts time on a staff (see `DrawMusic.Music.Editing.Time.insert_time/5`)."
  @spec insert_time(Score.t(), Context.t(), non_neg_integer(), pos_integer(), Note.staff()) ::
          result()
  defdelegate insert_time(score, ctx, at, ticks, staff), to: Time

  @doc "Moves notes along the scale (see `DrawMusic.Music.Editing.Pitches.move_steps/4`)."
  @spec move_steps(Score.t(), Context.t(), [id()], integer()) :: result()
  defdelegate move_steps(score, ctx, ids, delta), to: Pitches

  @doc "Moves a dragged note (see `DrawMusic.Music.Editing.Pitches.move_to_staff/5`)."
  @spec move_to_staff(Score.t(), Context.t(), id(), Note.staff(), integer()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  defdelegate move_to_staff(score, ctx, id, staff, step), to: Pitches

  @doc "Pastes a clipboard (see `DrawMusic.Music.Clipboard.paste/4`)."
  @spec paste(Score.t(), Context.t(), Clipboard.t(), non_neg_integer()) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  defdelegate paste(score, ctx, clipboard, at), to: Clipboard

  @doc "Places a chord (see `DrawMusic.Music.Editing.Place.place_chord/5`)."
  @spec place_chord(Score.t(), Context.t(), non_neg_integer(), Placement.t(), [{integer(), -2..2}]) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  defdelegate place_chord(score, ctx, index, placement, pitches), to: Place

  @doc "Places a note (see `DrawMusic.Music.Editing.Place.place_note/4`)."
  @spec place_note(Score.t(), Context.t(), non_neg_integer(), Placement.t()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  defdelegate place_note(score, ctx, index, placement), to: Place

  @doc "Places a rest (see `DrawMusic.Music.Editing.Place.place_rest/4`)."
  @spec place_rest(Score.t(), Context.t(), non_neg_integer(), Placement.t()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  defdelegate place_rest(score, ctx, index, placement), to: Place

  @doc "Puts notes on a staff (see `DrawMusic.Music.Editing.Pitches.put_on_staff/4`)."
  @spec put_on_staff(Score.t(), Context.t(), [id()], Note.staff()) :: result()
  defdelegate put_on_staff(score, ctx, ids, staff), to: Pitches

  @doc "Re-bars a score (see `DrawMusic.Music.Editing.Time.rebar_to/3`)."
  @spec rebar_to(Score.t(), Context.t(), Context.t()) :: result()
  defdelegate rebar_to(score, from_ctx, to_ctx), to: Time

  @doc "Removes events (see `DrawMusic.Music.Editing.Time.remove/3`)."
  @spec remove(Score.t(), Context.t(), [id()]) :: result()
  defdelegate remove(score, ctx, ids), to: Time

  @doc "Plays events backwards (see `DrawMusic.Music.Editing.Time.reverse/3`)."
  @spec reverse(Score.t(), Context.t(), [id()]) :: result()
  defdelegate reverse(score, ctx, ids), to: Time

  @doc "Ids of the events in a range (see `DrawMusic.Music.Editing.Time.select_range/5`)."
  @spec select_range(Score.t(), Context.t(), integer(), integer()) :: [id()]
  @spec select_range(Score.t(), Context.t(), integer(), integer(), [Note.staff()]) :: [id()]
  defdelegate select_range(score, ctx, from, to, staves \\ [:treble, :bass]), to: Time

  @doc "Sets alterations (see `DrawMusic.Music.Editing.Pitches.set_alter/4`)."
  @spec set_alter(Score.t(), Context.t(), [id()], -2..2) :: result()
  defdelegate set_alter(score, ctx, ids, alter), to: Pitches

  @doc "Sets dots (see `DrawMusic.Music.Editing.Values.set_dots/4`)."
  @spec set_dots(Score.t(), Context.t(), [id()], 0..2) :: result()
  defdelegate set_dots(score, ctx, ids, dots), to: Values

  @doc "Sets a length (see `DrawMusic.Music.Editing.Values.set_value/5`)."
  @spec set_value(Score.t(), Context.t(), [id()], Duration.value(), 0..2) :: result()
  defdelegate set_value(score, ctx, ids, value, dots), to: Values

  @doc "Moves events in time (see `DrawMusic.Music.Editing.Time.shift/4`)."
  @spec shift(Score.t(), Context.t(), [id()], integer()) :: result()
  defdelegate shift(score, ctx, ids, beats), to: Time

  @doc "Splits events in two (see `DrawMusic.Music.Editing.Values.split/3`)."
  @spec split(Score.t(), Context.t(), [id()]) :: {:ok, Score.t(), [id()]} | {:error, reason()}
  defdelegate split(score, ctx, ids), to: Values

  @doc "Ties two notes, given in either order (see `DrawMusic.Music.Ties.tie/4`)."
  @spec tie(Score.t(), Context.t(), id(), id()) :: result()
  defdelegate tie(score, ctx, id_a, id_b), to: Ties

  @doc "Turns a rest into a note (see `DrawMusic.Music.Editing.Values.to_note/5`)."
  @spec to_note(Score.t(), Context.t(), id(), integer(), -2..2) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  defdelegate to_note(score, ctx, id, step, alter), to: Values

  @doc "Turns notes into a rest (see `DrawMusic.Music.Editing.Values.to_rest/3`)."
  @spec to_rest(Score.t(), Context.t(), [id()]) :: {:ok, Score.t(), id()} | {:error, reason()}
  defdelegate to_rest(score, ctx, ids), to: Values

  @doc "Transposes by semitones (see `DrawMusic.Music.Editing.Pitches.transpose_chromatic/4`)."
  @spec transpose_chromatic(Score.t(), Context.t(), [id()], integer()) :: result()
  defdelegate transpose_chromatic(score, ctx, ids, semitones), to: Pitches

  @doc "Transposes by an interval (see `DrawMusic.Music.Editing.Pitches.transpose_interval/5`)."
  @spec transpose_interval(Score.t(), Context.t(), [id()], integer(), integer()) :: result()
  defdelegate transpose_interval(score, ctx, ids, steps, semitones), to: Pitches

  @doc "Removes the ties into and out of a note (see `DrawMusic.Music.Ties.untie/2`)."
  @spec untie(Score.t(), id()) :: Score.t()
  defdelegate untie(score, id), to: Ties
end
