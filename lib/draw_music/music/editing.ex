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
  """

  alias DrawMusic.Music.{
    Clipboard,
    Context,
    Duration,
    Entry,
    Fillers,
    Measure,
    Note,
    Pitch,
    Placement,
    Rest,
    Score,
    Spans,
    StaffCrossing,
    TempoChange,
    Ties,
    Timeline
  }

  alias DrawMusic.Music.Editing.Rebuild

  @values Duration.values()

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

  ## Placing

  @doc """
  Places a note in measure `index` as `placement` describes (its `step` and
  `alter` give the pitch). Without a voice, the note goes in the lowest
  voice it fits.
  """
  @spec place_note(Score.t(), Context.t(), non_neg_integer(), Placement.t()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def place_note(%Score{} = score, %Context{} = ctx, index, %Placement{} = placement) do
    build = &[new_note(placement, &1, placement.step, placement.alter)]

    with {:ok, score, [note]} <- place(score, ctx, index, placement, build) do
      {:ok, score, note.id}
    end
  end

  @doc """
  Places a chord: one note per `{step, alter}` in `pitches`, all at the
  placement's position and length, in one voice (the placement's own step
  and alter are not used).
  """
  @spec place_chord(Score.t(), Context.t(), non_neg_integer(), Placement.t(), [{integer(), -2..2}]) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  def place_chord(%Score{} = score, %Context{} = ctx, index, %Placement{} = placement, pitches) do
    build = fn voice ->
      Enum.map(pitches, fn {step, alter} -> new_note(placement, voice, step, alter) end)
    end

    with {:ok, score, notes} <- place(score, ctx, index, placement, build) do
      {:ok, score, Enum.map(notes, & &1.id)}
    end
  end

  @doc """
  Places a rest in measure `index` as `placement` describes (its pitch is
  not used); without a voice, in the lowest voice it fits.
  """
  @spec place_rest(Score.t(), Context.t(), non_neg_integer(), Placement.t()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def place_rest(%Score{} = score, %Context{} = ctx, index, %Placement{} = placement) do
    build = fn voice ->
      [Rest.from(placement, id: Ecto.UUID.generate(), voice: voice)]
    end

    with {:ok, score, [rest]} <- place(score, ctx, index, placement, build) do
      {:ok, score, rest.id}
    end
  end

  # Overwriting: the time is cleared first, so the first voice takes it.
  defp place(score, ctx, index, %Placement{overwrite: true} = placement, build) do
    events = build.(placement.voice || 1)

    with {:ok, start} <- locate(score, ctx, index, hd(events), placement.cross_bar) do
      new_entries = Enum.map(events, &%{Timeline.entry(&1, 0) | start: start})
      entries = clear_span(Timeline.flatten(score, ctx), new_entries)

      with {:ok, score} <- Rebuild.rebuild(score, ctx, entries ++ new_entries) do
        {:ok, score, events}
      end
    end
  end

  # Tries the requested voice, or each voice in turn; returns the first
  # success or the first voice's error.
  defp place(score, ctx, index, %Placement{voice: voice, cross_bar: cross?}, build) do
    with :ok <- not_already_there(score, ctx, index, build.(1), cross?) do
      place_in_a_voice(score, ctx, index, voice, build, cross?)
    end
  end

  # The new entries' time on their staff, in every voice, becomes theirs:
  # an item sounding into it from earlier is shortened to end where it
  # starts, and every other item touching it goes (rests refill whatever
  # of its time is left uncovered).
  defp clear_span(entries, [first | _] = new_entries) do
    staff = first.event.staff
    from = first.start
    to = Enum.max(Enum.map(new_entries, &Entry.end_tick/1))

    Enum.flat_map(entries, fn
      %{event: %{staff: ^staff}} = entry
      when entry.start < to and from < entry.start + entry.ticks ->
        trim_before(entry, from)

      entry ->
        [entry]
    end)
  end

  defp trim_before(entry, from) when entry.start < from do
    [%{entry | ticks: from - entry.start, event: Ties.put(entry.event, nil)}]
  end

  defp trim_before(_entry, _from), do: []

  # The same pitch, start and length already on the staff, in any voice, is
  # a duplicate: placing it again in another voice would only double it.
  # (Two voices may share a pitch with different lengths.)
  defp not_already_there(score, ctx, index, [first | _] = events, cross?) do
    with {:ok, start} <- locate(score, ctx, index, first, cross?) do
      taken =
        for %{kind: :note, start: ^start, ticks: ticks, event: %{staff: staff, step: step}} <-
              Timeline.flatten(score, ctx),
            staff == first.staff,
            into: MapSet.new(),
            do: {step, ticks}

      case Enum.any?(events, &({Map.get(&1, :step), Duration.ticks(&1.value, &1.dots)} in taken)) do
        true -> {:error, :duplicate}
        false -> :ok
      end
    end
  end

  defp place_in_a_voice(score, ctx, index, voice, build, cross?) do
    voice
    |> voices_to_try()
    |> Enum.reduce_while(nil, fn voice, first_error ->
      events = build.(voice)

      case place_events(score, ctx, index, events, cross?) do
        {:ok, score} -> {:halt, {:ok, score, events}}
        error -> {:cont, first_error || error}
      end
    end)
  end

  defp voices_to_try(nil), do: Note.voices()
  defp voices_to_try(voice), do: [voice]

  defp place_events(score, ctx, index, [first | _] = events, cross?) do
    with {:ok, start} <- locate(score, ctx, index, first, cross?) do
      Rebuild.add(score, ctx, Enum.map(events, &%{Timeline.entry(&1, 0) | start: start}))
    end
  end

  defp new_note(%Placement{} = placement, voice, step, alter) do
    Note.from(placement, id: Ecto.UUID.generate(), voice: voice, step: step, alter: alter)
  end

  # The tick where `event` starts in bar `index`. It must fit in the bar, or,
  # placed to cross bar lines (`cross?`), just start inside it.
  defp locate(score, ctx, index, event, cross?) when is_integer(index) and index >= 0 do
    case Enum.at(Timeline.bars(score, ctx), index) do
      nil ->
        {:error, :no_such_measure}

      {start, _capacity} = bar ->
        at = start + event.offset

        with :ok <- ensure(Timeline.fits?(bar, at, room(event, cross?)), :measure_full),
             do: {:ok, at}
    end
  end

  defp locate(_score, _ctx, _index, _event, _cross?), do: {:error, :no_such_measure}

  # How much of `event` must fit in its bar: one tick (its start) when it may
  # cross the bar line, else all of it.
  defp room(_event, true = _cross?), do: 1
  defp room(event, _cross?), do: Duration.ticks(event.value, event.dots)

  ## Changing selected events

  @doc "Removes the notes and rests with the given ids."
  @spec remove(Score.t(), Context.t(), [id()]) :: result()
  def remove(%Score{} = score, %Context{} = ctx, ids) do
    {_removed, kept} = Entry.select(Timeline.flatten(score, ctx), ids)
    Rebuild.rebuild(score, ctx, kept)
  end

  @doc """
  Sets the dots of the given events. The result must still fit in each
  event's measure (`:measure_full`), and each value must take that many
  dots (`:unrepresentable`: a 256th none, a 128th one); dot a whole chord
  together.
  """
  @spec set_dots(Score.t(), Context.t(), [id()], 0..2) :: result()
  def set_dots(%Score{} = score, %Context{} = ctx, ids, dots) when dots in 0..2 do
    bars = Timeline.bars(score, ctx)

    Rebuild.map_selected(score, ctx, ids, fn entry ->
      with :ok <- ensure(Duration.dots_allowed?(entry.event.value, dots), :unrepresentable),
           ticks = Duration.ticks(entry.event.value, dots),
           :ok <- fits_bar(bars, entry.start, ticks) do
        {:ok, %{entry | ticks: ticks, event: Fillers.claim(%{entry.event | dots: dots})}}
      end
    end)
  end

  @doc "Sets the absolute alteration (-2..2) of the given notes."
  @spec set_alter(Score.t(), Context.t(), [id()], -2..2) :: result()
  def set_alter(%Score{} = score, %Context{} = ctx, ids, alter) when alter in -2..2 do
    Rebuild.map_selected(score, ctx, ids, &note_only(&1, fn note -> %{note | alter: alter} end))
  end

  @doc """
  Moves the given notes `delta` steps up (positive) or down the scale of the
  key. Each keeps its accidental: the key's version of its new letter,
  sharpened or flattened as much as it was (F♯ up a step in C major is G♯;
  the key's own F♯ in G major goes to G). A note taken past its staff's
  half of the gap between the staves moves to the other staff
  (`DrawMusic.Music.StaffCrossing`).
  """
  @spec move_steps(Score.t(), Context.t(), [id()], integer()) :: result()
  def move_steps(%Score{} = score, %Context{} = ctx, ids, delta) when is_integer(delta) do
    move_pitches(score, ctx, ids, fn note ->
      step = note.step + delta
      %{note | step: step, alter: kept_alter(ctx.sf, note, step)}
    end)
  end

  @doc """
  Puts the notes among `ids` on `staff` at their own pitches, however far
  from it they are (a left-hand part written high on the bass staff, say).
  Each joins a note there that starts and ends with it as a chord, or else
  goes in the lowest voice with room; rests among `ids` stay where they are.
  """
  @spec put_on_staff(Score.t(), Context.t(), [id()], Note.staff()) :: result()
  def put_on_staff(%Score{} = score, %Context{} = ctx, ids, staff) do
    with {:ok, entries} <- StaffCrossing.restaff_all(Timeline.flatten(score, ctx), ids, staff) do
      Rebuild.rebuild(score, ctx, entries)
    end
  end

  @doc """
  Moves note `id` onto `step` of `staff` (where a single dragged note was
  let go), keeping its time, value, dots and accidental (as
  `move_steps/4`). Past its staff's half of the gap between the staves it
  goes to the other staff (`DrawMusic.Music.StaffCrossing`). On
  another staff it leaves its chord and voice, and joins a note there that
  starts and ends with it as a chord, or else goes in the lowest voice with
  room. Returns its id.
  """
  @spec move_to_staff(Score.t(), Context.t(), id(), Note.staff(), integer()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def move_to_staff(%Score{} = score, %Context{} = ctx, id, staff, step) do
    entries = Timeline.flatten(score, ctx)

    case Entry.find(entries, id) do
      {:ok, %{kind: :note, event: note} = entry} ->
        moved = %{entry | event: %{note | step: step, alter: kept_alter(ctx.sf, note, step)}}

        with {:ok, entries} <-
               entries
               |> replace_entry(id, [moved])
               |> StaffCrossing.restaff(id, StaffCrossing.staff_for(staff, step)),
             {:ok, score} <- Rebuild.rebuild(score, ctx, entries) do
          {:ok, score, id}
        end

      {:ok, _rest} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Moves the given events `beats` time-signature units later (positive) or
  earlier. Events crossing a bar line are split into tied notes; measures
  are appended when needed.
  """
  @spec shift(Score.t(), Context.t(), [id()], integer()) :: result()
  def shift(%Score{} = score, %Context{} = ctx, ids, beats) when is_integer(beats) do
    delta = beats * Context.beat_ticks(ctx)

    with {:ok, entries} <-
           Rebuild.map_entries(score, ctx, ids, fn entry ->
             {:ok, %{entry | start: entry.start + delta, event: Fillers.claim(entry.event)}}
           end) do
      Rebuild.rebuild(score, ctx, Ties.merge(entries))
    end
  end

  @doc """
  Inserts `ticks` of time at absolute tick `at` on one staff: every event on
  `staff` starting at or after `at` moves right by `ticks`, through the end
  of the piece. An event sounding across `at` is split there and its tail
  moves; the tie between a note's halves is dropped, since they no longer
  touch. Filler rests don't move: the gaps between moved events move with
  them, and trailing filler shrinks, so bars are appended only when notes
  or placed rests run past the last one. The other staff is untouched.
  """
  @spec insert_time(Score.t(), Context.t(), non_neg_integer(), pos_integer(), Note.staff()) ::
          result()
  def insert_time(%Score{} = score, %Context{} = ctx, at, ticks, staff)
      when is_integer(at) and at >= 0 and is_integer(ticks) and ticks > 0 do
    entries =
      score
      |> Timeline.flatten(ctx)
      |> Enum.reject(&Fillers.filler?/1)
      |> Enum.flat_map(fn
        %{event: %{staff: ^staff}} = entry when entry.start >= at ->
          [%{entry | start: entry.start + ticks}]

        %{event: %{staff: ^staff}} = entry when entry.start + entry.ticks > at ->
          split_at(entry, at, ticks)

        entry ->
          [entry]
      end)

    Rebuild.rebuild(score, ctx, Ties.merge(entries))
  end

  @doc """
  Where an insert at tick `at` on `staff` lands, like a text cursor among
  characters: every note and rest is one, the rests that end the piece
  included, so it lands where it's put, never inside an item. Where a note
  or rest starts, there (in front of it); inside a note, where it ends;
  inside a rest, in front of it, so it stays in the bar it was put in.
  """
  @spec insert_point(Score.t(), Context.t(), Note.staff(), non_neg_integer()) ::
          non_neg_integer()
  def insert_point(%Score{} = score, %Context{} = ctx, staff, at) do
    spans =
      for %{event: %{staff: ^staff}} = entry <- Timeline.flatten(score, ctx),
          do: {entry.kind, entry.start, Entry.end_tick(entry)}

    Spans.cursor(spans, at)
  end

  @doc """
  Deletes events and closes the gap on each staff they were on: every
  later event on that staff moves left by the time emptied before it. Time
  another voice on the staff still sounds (with a note or a placed rest) is
  not a gap. Deleting a filler rest closes its gap.
  """
  @spec delete(Score.t(), Context.t(), [id()]) :: result()
  def delete(%Score{} = score, %Context{} = ctx, ids) do
    {gone, kept} = Entry.select(Timeline.flatten(score, ctx), ids)

    gaps =
      gone
      |> Enum.group_by(& &1.event.staff)
      |> Map.new(fn {staff, removed} ->
        covers = Enum.filter(kept, &(&1.event.staff == staff and not Fillers.filler?(&1)))
        {staff, Spans.emptied(removed, covers)}
      end)

    shifted =
      Enum.map(kept, fn entry ->
        closed =
          for {from, to} <- Map.get(gaps, entry.event.staff, []), to <= entry.start do
            to - from
          end

        %{entry | start: entry.start - Enum.sum(closed)}
      end)

    Rebuild.rebuild(score, ctx, Ties.merge(shifted))
  end

  @doc "Moves notes by `semitones`, spelled to suit the key."
  @spec transpose_chromatic(Score.t(), Context.t(), [id()], integer()) :: result()
  def transpose_chromatic(%Score{} = score, %Context{} = ctx, ids, semitones)
      when is_integer(semitones) do
    move_pitches(score, ctx, ids, fn note ->
      {step, alter} = Pitch.spell(Note.midi(note) + semitones, ctx.sf)
      %{note | step: step, alter: alter}
    end)
  end

  @doc """
  Moves notes by an exact interval: the letter moves `steps` and the
  alteration makes up `semitones` (a major third up is 2 steps, 4
  semitones). A spelling needing more than a double sharp or flat is
  re-spelled for the key.
  """
  @spec transpose_interval(Score.t(), Context.t(), [id()], integer(), integer()) :: result()
  def transpose_interval(%Score{} = score, %Context{} = ctx, ids, steps, semitones)
      when is_integer(steps) and is_integer(semitones) do
    move_pitches(score, ctx, ids, fn note ->
      {step, alter} = Pitch.transpose(note.step, note.alter, steps, semitones, ctx.sf)
      %{note | step: step, alter: alter}
    end)
  end

  @doc """
  Plays the events backwards within the time they span. Ties inside the
  selection are flipped so they still point forward; ties into or out of
  it are dropped.
  """
  @spec reverse(Score.t(), Context.t(), [id()]) :: result()
  def reverse(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    entries = Timeline.flatten(score, ctx)

    case Entry.select(entries, ids) do
      {[], _others} ->
        {:ok, score}

      {selected, _others} ->
        sum = Spans.mirror_sum(selected)
        flipped = Ties.flipped(selected, ids)
        Rebuild.rebuild(score, ctx, Enum.map(entries, &mirror(&1, ids, sum, flipped)))
    end
  end

  defp mirror(entry, ids, sum, flipped) do
    if entry.event.id in ids do
      %{
        entry
        | start: sum - Entry.end_tick(entry),
          event: Ties.put(entry.event, flipped[entry.event.id])
      }
    else
      entry
    end
  end

  @doc """
  Splits a note or rest into two. An undotted value becomes two of the next
  shorter value; a dotted one becomes the same value with one dot fewer plus
  the remainder (dotted quarter → quarter + eighth). A note's halves are tied.
  Returns the ids of the halves, head then tail for each event; heads keep
  the events' ids. Give the ids of a whole chord (see `chord_ids/3`) to
  split it together.
  """
  @spec split(Score.t(), Context.t(), [id()]) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  def split(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, [first | _] = chosen} <- Entry.find_all(entries, ids),
         {:ok, head, tail} <- halves(first.event.value, first.event.dots),
         pieces = Map.new(chosen, &{&1.event.id, split_entry(&1, head, tail)}),
         {:ok, score} <-
           Rebuild.rebuild(
             score,
             ctx,
             Enum.flat_map(entries, &Map.get(pieces, &1.event.id, [&1]))
           ) do
      {:ok, score, for(entry <- chosen, piece <- pieces[entry.event.id], do: piece.event.id)}
    end
  end

  defp split_entry(entry, {head_value, head_dots}, {tail_value, tail_dots}) do
    second = Ecto.UUID.generate()
    head_ticks = Duration.ticks(head_value, head_dots)

    event = Fillers.claim(entry.event)

    head = %{
      entry
      | ticks: head_ticks,
        event: Ties.put(%{event | value: head_value, dots: head_dots}, second)
    }

    tail = %{
      entry
      | start: entry.start + head_ticks,
        ticks: entry.ticks - head_ticks,
        event: %{event | id: second, value: tail_value, dots: tail_dots}
    }

    [head, tail]
  end

  @doc """
  Ids of the chord `id` belongs to: the notes of its staff and voice that
  start and end with it (just `[id]` for a rest or a lone note).
  """
  @spec chord_ids(Score.t(), Context.t(), id()) :: [id()]
  def chord_ids(%Score{} = score, %Context{} = ctx, id) do
    entries = Timeline.flatten(score, ctx)

    case Entry.find(entries, id) do
      {:ok, %{kind: :note} = entry} ->
        for other <- entries, same_chord?(entry, other), do: other.event.id

      _rest_or_missing ->
        [id]
    end
  end

  @doc """
  Adds a note to the chord `id` belongs to: `steps` scale steps above its
  top note (positive) or below its bottom note (negative), on the key's
  version of that letter. Returns the new note's id.
  """
  @spec add_to_chord(Score.t(), Context.t(), id(), integer()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def add_to_chord(%Score{} = score, %Context{} = ctx, id, steps)
      when is_integer(steps) and steps != 0 do
    entries = Timeline.flatten(score, ctx)

    case Entry.find(entries, id) do
      {:ok, %{kind: :note} = entry} ->
        chord = Enum.filter(entries, &same_chord?(entry, &1))

        edge =
          if steps > 0,
            do: Enum.max_by(chord, & &1.event.step),
            else: Enum.min_by(chord, & &1.event.step)

        step = edge.event.step + steps

        note = %{
          edge.event
          | id: Ecto.UUID.generate(),
            step: step,
            alter: Pitch.in_key(step, ctx.sf),
            tie_to: nil
        }

        with {:ok, score} <- Rebuild.add(score, ctx, [%{edge | event: note}]),
             do: {:ok, score, note.id}

      {:ok, _rest} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  # Notes of one chord share its key (`Entry.chord_key/1`): a voice's notes
  # that start together have the same length, or the edit was refused.
  defp same_chord?(%{kind: :note} = entry, %{kind: :note} = other) do
    Entry.chord_key(entry) == Entry.chord_key(other)
  end

  defp same_chord?(_entry, _other), do: false

  defp halves(value, 0) do
    case Enum.drop_while(@values, &(&1 != value)) do
      [_value, shorter | _] -> {:ok, {shorter, 0}, {shorter, 0}}
      _shortest -> {:error, :unrepresentable}
    end
  end

  defp halves(value, dots) do
    remainder = Duration.ticks(value, dots) - Duration.ticks(value, dots - 1)

    case Duration.decompose(remainder) do
      {:ok, [tail]} -> {:ok, {value, dots - 1}, tail}
      _ -> {:error, :unrepresentable}
    end
  end

  @doc """
  Changes the length of a note or rest (or, given a chord's ids, of the
  whole chord) in place. It must still fit in its bar (`:measure_full`) and
  its voice (`:overlap`).
  """
  @spec set_value(Score.t(), Context.t(), [id()], Duration.value(), 0..2) :: result()
  def set_value(_score, _ctx, _ids, value, _dots) when value not in @values do
    {:error, :unrepresentable}
  end

  def set_value(%Score{} = score, %Context{} = ctx, ids, value, dots) when dots in 0..2 do
    entries = Timeline.flatten(score, ctx)

    with :ok <- ensure(Duration.dots_allowed?(value, dots), :unrepresentable),
         ticks = Duration.ticks(value, dots),
         {:ok, [first | _] = chosen} <- Entry.find_all(entries, ids),
         :ok <- fits_bar(Timeline.bars(score, ctx), first.start, ticks) do
      changed =
        Map.new(chosen, fn entry ->
          {entry.event.id,
           %{
             entry
             | ticks: ticks,
               event: Fillers.claim(%{entry.event | value: value, dots: dots})
           }}
        end)

      Rebuild.rebuild(score, ctx, Enum.map(entries, &Map.get(changed, &1.event.id, &1)))
    end
  end

  # A new length for what starts at `start` must still end in its bar.
  defp fits_bar(bars, start, ticks) do
    ensure(Timeline.fits?(Timeline.bar_at(bars, start), start, ticks), :measure_full)
  end

  @doc """
  Turns a note (or, given a chord's ids, the whole chord) into one rest of
  the same length and position, keeping the first note's id; ties into or
  out of it are removed.
  """
  @spec to_rest(Score.t(), Context.t(), [id()]) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def to_rest(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, [%{event: %{id: first_id}} = first | _]} <- Entry.find_all(entries, ids),
         rest = Rest.from(first.event, id: first_id),
         {_others, kept} = Entry.select(entries, List.delete(ids, first_id)),
         replaced = replace_entry(kept, first_id, [%{first | kind: :rest, event: rest}]),
         {:ok, score} <- Rebuild.rebuild(score, ctx, replaced) do
      {:ok, score, first_id}
    end
  end

  @doc """
  Turns a rest into a note of the same length and position (keeping its
  id), on `step` with `alter`.
  """
  @spec to_note(Score.t(), Context.t(), id(), integer(), -2..2) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def to_note(%Score{} = score, %Context{} = ctx, id, step, alter) when alter in -2..2 do
    entries = Timeline.flatten(score, ctx)

    with {:ok, entry} <- Entry.find(entries, id),
         note = Note.from(entry.event, id: id, step: step, alter: alter),
         note_entry = %{entry | kind: :note, event: note},
         {:ok, score} <- Rebuild.rebuild(score, ctx, replace_entry(entries, id, [note_entry])) do
      {:ok, score, id}
    end
  end

  @doc """
  Turns each note among `ids` into a chord: the whole chord it belongs to
  (its staff, voice and start) is replaced by the pitches `pitches_for`
  gives for that chord's lowest note, at the same time, length and voice.
  The lowest note keeps its id for the chord's first pitch; ties into or out
  of the replaced notes go. Returns the ids of every new chord's notes.
  """
  @spec chordify(Score.t(), Context.t(), [id()], (integer(), -2..2 ->
                                                    {:ok, [{integer(), -2..2}]}
                                                    | {:error, reason()})) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  def chordify(%Score{} = score, %Context{} = ctx, ids, pitches_for)
      when is_function(pitches_for, 2) do
    entries = Timeline.flatten(score, ctx)
    ids = MapSet.new(ids)

    chords =
      entries
      |> Enum.filter(&(&1.kind == :note and &1.event.id in ids))
      |> Enum.map(&Entry.chord_key/1)
      |> Enum.uniq()

    with {:ok, entries, new_ids} <- rebuild_chords(entries, chords, pitches_for),
         {:ok, score} <- Rebuild.rebuild(score, ctx, entries) do
      {:ok, score, new_ids}
    end
  end

  defp rebuild_chords(entries, chords, pitches_for) do
    Enum.reduce_while(chords, {:ok, entries, []}, fn key, {:ok, entries, new_ids} ->
      {old, kept} = Enum.split_with(entries, &(&1.kind == :note and Entry.chord_key(&1) == key))
      root = Enum.min_by(old, & &1.event.step)

      case pitches_for.(root.event.step, root.event.alter) do
        {:ok, pitches} ->
          chord = chord_entries(root, pitches)
          {:cont, {:ok, kept ++ chord, new_ids ++ Enum.map(chord, & &1.event.id)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp chord_entries(root, pitches) do
    pitches
    |> Enum.with_index()
    |> Enum.map(fn {{step, alter}, i} ->
      id = if i == 0, do: root.event.id, else: Ecto.UUID.generate()
      %{root | event: %{root.event | id: id, step: step, alter: alter, tie_to: nil}}
    end)
  end

  @doc """
  Re-reads a score written against `from_ctx` into the bars of `to_ctx`
  (after a time signature or pickup change): every event keeps its time
  from the start, events crossing the new bar lines are split into ties,
  and the score keeps at least as many bars as the music spanned.
  """
  @spec rebar_to(Score.t(), Context.t(), Context.t()) :: result()
  def rebar_to(%Score{} = score, %Context{} = from_ctx, %Context{} = to_ctx) do
    bars = bars_spanning(to_ctx, Timeline.end_tick(score, from_ctx))
    fresh = %{Score.new(bars) | tempos: score.tempos}
    Rebuild.rebuild(fresh, to_ctx, Ties.merge(Timeline.flatten(score, from_ctx)))
  end

  # How many bars of `ctx` it takes to reach tick `last` (at least one).
  defp bars_spanning(ctx, last) do
    bars_after(Context.capacity(ctx, 0), last, Context.measure_ticks(ctx))
  end

  defp bars_after(first, last, _bar) when last <= first, do: 1
  defp bars_after(first, last, bar), do: 1 + div(last - first + bar - 1, bar)

  # A check as an edit step: `:ok`, or the reason it's refused.
  defp ensure(true, _reason), do: :ok
  defp ensure(false, reason), do: {:error, reason}

  defp replace_entry(entries, id, replacements) do
    Enum.flat_map(entries, fn
      %{event: %{id: ^id}} -> replacements
      entry -> [entry]
    end)
  end

  # Head up to `at` (keeping the id), tail moved `gap` later with a fresh id
  # and whatever tie the event had.
  defp split_at(entry, at, gap) do
    head = %{entry | ticks: at - entry.start, event: Ties.put(entry.event, nil)}

    tail = %{
      entry
      | start: at + gap,
        ticks: Entry.end_tick(entry) - at,
        event: %{entry.event | id: Ecto.UUID.generate()}
    }

    [head, tail]
  end

  defp note_only(%{kind: :note} = entry, fun), do: {:ok, %{entry | event: fun.(entry.event)}}
  defp note_only(entry, _fun), do: {:ok, entry}

  # A moved note's new alteration: the key's version of letter `step`,
  # sharpened or flattened as much as the note was from its own key letter.
  defp kept_alter(sf, note, step) do
    accidental = note.alter - Pitch.in_key(note.step, sf)

    (Pitch.in_key(step, sf) + accidental)
    |> max(-2)
    |> min(2)
  end

  # Changes the pitch of the notes among `ids` (`fun`, note to note); any
  # taken past their staff's half of the gap move to the other staff.
  defp move_pitches(score, ctx, ids, fun) do
    with {:ok, entries} <- Rebuild.map_entries(score, ctx, ids, &note_only(&1, fun)),
         {:ok, entries} <- StaffCrossing.settle(entries, ids) do
      Rebuild.rebuild(score, ctx, entries)
    end
  end

  ## Ties (`DrawMusic.Music.Ties`)

  @doc "Ties two notes, given in either order (see `DrawMusic.Music.Ties.tie/4`)."
  @spec tie(Score.t(), Context.t(), id(), id()) :: result()
  defdelegate tie(score, ctx, id_a, id_b), to: Ties

  @doc "Removes the ties into and out of a note."
  @spec untie(Score.t(), id()) :: Score.t()
  defdelegate untie(score, id), to: Ties

  ## Measures

  @doc """
  Inserts a measure of filler rests before `index` (`index == length`
  appends), dropping ties the new bar separates. Tempo changes after it
  move with the music.
  """
  @spec insert_measure(Score.t(), Context.t(), non_neg_integer()) :: result()
  def insert_measure(%Score{} = score, %Context{} = ctx, index) do
    with {:ok, score} <- empty_measure_at(score, index) do
      at = Context.span(ctx, index)
      tempos = shift_tempos(score.tempos, at, Context.capacity(ctx, index))
      {:ok, %{score | tempos: tempos} |> Ties.prune(ctx) |> fill_rests(ctx)}
    end
  end

  defp empty_measure_at(%Score{measures: measures} = score, index)
       when is_integer(index) and index >= 0 and index <= length(measures) do
    {:ok, %{score | measures: List.insert_at(measures, index, Measure.new())}}
  end

  defp empty_measure_at(_score, _index), do: {:error, :no_such_measure}

  @doc "Appends a measure of filler rests."
  @spec append_measure(Score.t(), Context.t()) :: result()
  def append_measure(%Score{measures: measures} = score, %Context{} = ctx) do
    insert_measure(score, ctx, length(measures))
  end

  @doc """
  Deletes measure `index` and its contents, its tempo changes included;
  later ones move back with the music. The last measure cannot be deleted,
  nor the pickup bar (remove the pickup in the settings instead).
  """
  @spec delete_measure(Score.t(), Context.t(), non_neg_integer()) :: result()
  def delete_measure(%Score{measures: [_only]}, _ctx, 0), do: {:error, :last_measure}

  def delete_measure(%Score{}, %Context{pickup_ticks: pickup}, 0) when pickup > 0 do
    {:error, :pickup_bar}
  end

  def delete_measure(%Score{measures: measures} = score, ctx, index)
      when is_integer(index) and index >= 0 and index < length(measures) do
    at = Context.span(ctx, index)
    length = Context.capacity(ctx, index)

    # A ramp ending inside the deleted bar now ends where the bar was.
    tempos =
      score.tempos
      |> Enum.reject(&(&1.tick >= at and &1.tick < at + length))
      |> Enum.map(fn
        %{to_tick: to} = change when is_integer(to) and to > at and to < at + length ->
          %{change | to_tick: at}

        change ->
          change
      end)
      |> shift_tempos(at + length, -length)

    {:ok, Ties.prune(%{score | measures: List.delete_at(measures, index), tempos: tempos}, ctx)}
  end

  def delete_measure(_score, _ctx, _index), do: {:error, :no_such_measure}

  # Tempo changes from tick `at` on move by `delta`; a rit. or accel. that
  # spans `at` keeps its start and moves its end. One left with no length
  # becomes a mark at its end tempo.
  defp shift_tempos(tempos, at, delta) do
    Enum.map(tempos, fn change ->
      change
      |> shift_field(:tick, at, delta)
      |> shift_field(:to_tick, at, delta)
      |> keep_ramp_forward()
    end)
  end

  defp shift_field(change, field, at, delta) do
    case Map.fetch!(change, field) do
      tick when is_integer(tick) and tick >= at -> Map.put(change, field, tick + delta)
      _before -> change
    end
  end

  defp keep_ramp_forward(%TempoChange{to_tick: to_tick, tick: tick} = change)
       when is_integer(to_tick) and to_tick <= tick do
    %{change | to_tick: nil, bpm: change.to_bpm, to_bpm: nil}
  end

  defp keep_ramp_forward(change), do: change

  ## Selection and clipboard

  @doc """
  Ids of the events starting in ticks `from..to-1` on the given staves. A
  filler rest counts only when it also ends within the range, so a band
  over a few notes doesn't take in a bar-long rest on the other staff.
  """
  @spec select_range(Score.t(), Context.t(), integer(), integer()) :: [id()]
  @spec select_range(Score.t(), Context.t(), integer(), integer(), [Note.staff()]) :: [id()]
  def select_range(%Score{} = score, %Context{} = ctx, from, to, staves \\ [:treble, :bass]) do
    for entry <- Timeline.flatten(score, ctx),
        entry.start >= from and entry.start < to,
        entry.event.staff in staves,
        not Fillers.filler?(entry) or Entry.end_tick(entry) <= to do
      entry.event.id
    end
  end

  @doc """
  Copies the given events. Positions are kept relative to the earliest
  one; ties to notes outside the selection are dropped.
  """
  @spec copy(Score.t(), Context.t(), [id()]) :: Clipboard.t()
  def copy(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    {selected, _others} = Entry.select(Timeline.flatten(score, ctx), ids)

    origin =
      selected
      |> Enum.map(& &1.start)
      |> Enum.min(fn -> 0 end)

    %Clipboard{
      entries:
        Enum.map(selected, fn entry ->
          %{entry | start: entry.start - origin, event: Ties.drop_outside(entry.event, ids)}
        end)
    }
  end

  @doc """
  Pastes a clipboard from `copy/3` starting at absolute tick `at`, with
  fresh ids. Returns the new ids.
  """
  @spec paste(Score.t(), Context.t(), Clipboard.t(), non_neg_integer()) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  def paste(%Score{} = score, %Context{} = ctx, %Clipboard{entries: entries}, at)
      when is_integer(at) and at >= 0 do
    fresh = Map.new(entries, &{&1.event.id, Ecto.UUID.generate()})

    pasted =
      Enum.map(entries, fn entry ->
        event = Ties.renumber(%{Fillers.claim(entry.event) | id: fresh[entry.event.id]}, fresh)
        %{entry | start: entry.start + at, event: event}
      end)

    entries =
      Ties.merge(Rebuild.clear_rests_under(Timeline.flatten(score, ctx), pasted) ++ pasted)

    with {:ok, score} <- Rebuild.rebuild(score, ctx, entries), do: {:ok, score, Map.values(fresh)}
  end

  ## Rests (`DrawMusic.Music.Fillers`)

  @doc "Rewrites the filler rests (see `DrawMusic.Music.Fillers.fill/2`)."
  @spec fill_rests(Score.t(), Context.t()) :: Score.t()
  defdelegate fill_rests(score, ctx), to: Fillers, as: :fill
end
