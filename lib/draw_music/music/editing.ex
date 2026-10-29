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
    Gaps,
    Measure,
    Note,
    Pitch,
    Placement,
    Rest,
    Score,
    Timeline
  }

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
      [
        %Rest{
          id: Ecto.UUID.generate(),
          staff: placement.staff,
          voice: voice,
          offset: placement.offset,
          value: placement.value,
          dots: placement.dots
        }
      ]
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

      with {:ok, score} <- rebuild(score, ctx, entries ++ new_entries) do
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
    to = Enum.max(Enum.map(new_entries, &(&1.start + &1.ticks)))

    Enum.flat_map(entries, fn
      %{event: %{staff: ^staff}} = entry
      when entry.start < to and from < entry.start + entry.ticks ->
        trim_before(entry, from)

      entry ->
        [entry]
    end)
  end

  defp trim_before(entry, from) when entry.start < from do
    [%{entry | ticks: from - entry.start, event: put_tie(entry.event, nil)}]
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
      add(score, ctx, Enum.map(events, &%{Timeline.entry(&1, 0) | start: start}))
    end
  end

  defp new_note(%Placement{} = placement, voice, step, alter) do
    %Note{
      id: Ecto.UUID.generate(),
      staff: placement.staff,
      voice: voice,
      offset: placement.offset,
      value: placement.value,
      dots: placement.dots,
      step: step,
      alter: alter
    }
  end

  defp locate(score, ctx, index, event, cross?) when is_integer(index) and index >= 0 do
    case Enum.at(Timeline.bars(score, ctx), index) do
      nil ->
        {:error, :no_such_measure}

      {start, capacity} ->
        place_within(
          start,
          capacity,
          event.offset,
          Duration.ticks(event.value, event.dots),
          cross?
        )
    end
  end

  defp locate(_score, _ctx, _index, _event, _cross?), do: {:error, :no_such_measure}

  defp place_within(start, capacity, offset, _ticks, true = _cross?)
       when offset >= 0 and offset < capacity do
    {:ok, start + offset}
  end

  defp place_within(start, capacity, offset, ticks, _cross?)
       when offset >= 0 and offset + ticks <= capacity do
    {:ok, start + offset}
  end

  defp place_within(_start, _capacity, _offset, _ticks, _cross?), do: {:error, :measure_full}

  ## Changing selected events

  @doc "Removes the notes and rests with the given ids."
  @spec remove(Score.t(), Context.t(), [id()]) :: result()
  def remove(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    rebuild(score, ctx, Enum.reject(Timeline.flatten(score, ctx), &(&1.event.id in ids)))
  end

  @doc """
  Sets the dots of the given events. The result must still fit in each
  event's measure (`:measure_full`); dot a whole chord together.
  """
  @spec set_dots(Score.t(), Context.t(), [id()], 0..2) :: result()
  def set_dots(%Score{} = score, %Context{} = ctx, ids, dots) when dots in 0..2 do
    bars = Timeline.bars(score, ctx)

    map_selected(score, ctx, ids, fn entry ->
      ticks = Duration.ticks(entry.event.value, dots)

      with :ok <- fits_bar(bars, entry.start, ticks) do
        {:ok, %{entry | ticks: ticks, event: claim(%{entry.event | dots: dots})}}
      end
    end)
  end

  @doc "Sets the absolute alteration (-2..2) of the given notes."
  @spec set_alter(Score.t(), Context.t(), [id()], -2..2) :: result()
  def set_alter(%Score{} = score, %Context{} = ctx, ids, alter) when alter in -2..2 do
    map_selected(score, ctx, ids, &note_only(&1, fn note -> %{note | alter: alter} end))
  end

  @doc """
  Moves the given notes `delta` steps up (positive) or down the scale of the
  key: each lands on the key's own version of its new letter.
  """
  @spec move_steps(Score.t(), Context.t(), [id()], integer()) :: result()
  def move_steps(%Score{} = score, %Context{} = ctx, ids, delta) when is_integer(delta) do
    map_selected(score, ctx, ids, fn entry ->
      note_only(entry, fn note ->
        step = note.step + delta
        %{note | step: step, alter: Pitch.key_alter(ctx.sf, Pitch.letter(step))}
      end)
    end)
  end

  @doc """
  Moves note `id` onto `step` of `staff`, keeping its time, value and dots;
  it lands on the key's version of the new letter. On another staff it
  leaves its chord and voice and goes in the lowest voice it fits there.
  Returns the moved note's id, which is new when the staff changes.
  """
  @spec move_to_staff(Score.t(), Context.t(), id(), Note.staff(), integer()) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def move_to_staff(%Score{} = score, %Context{} = ctx, id, staff, step) do
    case find_entry(Timeline.flatten(score, ctx), id) do
      {:ok, %{kind: :note, event: %{staff: ^staff} = note}} ->
        with {:ok, score} <- move_steps(score, ctx, [id], step - note.step) do
          {:ok, score, id}
        end

      {:ok, %{kind: :note} = entry} ->
        restaff(score, ctx, entry, staff, step)

      {:ok, _rest} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  defp restaff(score, ctx, %{event: note} = entry, staff, step) do
    {index, {bar_start, _capacity}} =
      score
      |> Timeline.bars(ctx)
      |> Enum.with_index()
      |> Enum.find_value(fn {{start, capacity} = bar, index} ->
        entry.start >= start and entry.start < start + capacity and {index, bar}
      end)

    placement = %Placement{
      staff: staff,
      offset: entry.start - bar_start,
      value: note.value,
      dots: note.dots,
      step: step,
      alter: Pitch.key_alter(ctx.sf, Pitch.letter(step))
    }

    with {:ok, score} <- remove(score, ctx, [note.id]) do
      place_note(score, ctx, index, placement)
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
           map_entries(score, ctx, ids, fn entry ->
             {:ok, %{entry | start: entry.start + delta, event: claim(entry.event)}}
           end) do
      rebuild(score, ctx, merge_ties(entries))
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
      |> Enum.reject(&filler?/1)
      |> Enum.flat_map(fn
        %{event: %{staff: ^staff}} = entry when entry.start >= at ->
          [%{entry | start: entry.start + ticks}]

        %{event: %{staff: ^staff}} = entry when entry.start + entry.ticks > at ->
          split_at(entry, at, ticks)

        entry ->
          [entry]
      end)

    rebuild(score, ctx, merge_ties(entries))
  end

  @doc """
  Where an insert at tick `at` on `staff` lands, like a text cursor: never
  inside an item and never leaving a gap. At or past the end of the
  staff's music (into the rests that end the piece) it lands where the
  music ends (the start of the piece if there is none); where a note or
  rest starts, there; inside one, where it ends.
  """
  @spec insert_point(Score.t(), Context.t(), Note.staff(), non_neg_integer()) ::
          non_neg_integer()
  def insert_point(%Score{} = score, %Context{} = ctx, staff, at) do
    entries = Enum.filter(Timeline.flatten(score, ctx), &(&1.event.staff == staff))

    music_end =
      entries
      |> Enum.reject(&filler?/1)
      |> Enum.map(&(&1.start + &1.ticks))
      |> Enum.max(fn -> 0 end)

    spans =
      for entry <- entries, entry.start < music_end, do: {entry.start, entry.start + entry.ticks}

    cursor(spans, min(at, music_end))
  end

  # Out of whatever item `at` falls inside, to where it ends.
  defp cursor(spans, at) do
    case Enum.find(spans, fn {from, to} -> from < at and at < to end) do
      nil -> at
      {_from, to} -> cursor(spans, to)
    end
  end

  @doc """
  Deletes events and closes the gap on each staff they were on: every
  later event on that staff moves left by the time emptied before it. Time
  another voice on the staff still sounds (with a note or a placed rest) is
  not a gap. Deleting a filler rest closes its gap.
  """
  @spec delete(Score.t(), Context.t(), [id()]) :: result()
  def delete(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)

    {gone, kept} =
      score
      |> Timeline.flatten(ctx)
      |> Enum.split_with(&(&1.event.id in ids))

    gaps =
      gone
      |> Enum.group_by(& &1.event.staff)
      |> Map.new(fn {staff, removed} ->
        covers = Enum.filter(kept, &(&1.event.staff == staff and not filler?(&1)))
        {staff, emptied(removed, covers)}
      end)

    shifted =
      Enum.map(kept, fn entry ->
        closed =
          for {from, to} <- Map.get(gaps, entry.event.staff, []), to <= entry.start do
            to - from
          end

        %{entry | start: entry.start - Enum.sum(closed)}
      end)

    rebuild(score, ctx, merge_ties(shifted))
  end

  # The removed events' spans, merged, minus time still covered by others.
  defp emptied(removed, kept) do
    covers = Enum.map(kept, &{&1.start, &1.start + &1.ticks})

    removed
    |> Enum.map(&{&1.start, &1.start + &1.ticks})
    |> merge_spans()
    |> Enum.flat_map(fn span -> Enum.reduce(covers, [span], &cut_out/2) end)
  end

  defp merge_spans(spans) do
    spans
    |> Enum.sort()
    |> Enum.reduce([], fn
      {from, to}, [{prev_from, prev_to} | rest] when from <= prev_to ->
        [{prev_from, max(to, prev_to)} | rest]

      span, acc ->
        [span | acc]
    end)
    |> Enum.reverse()
  end

  # Removes the cover {cs, ce} from each span.
  defp cut_out({cs, ce}, spans) do
    Enum.flat_map(spans, fn {s, e} ->
      Enum.reject([{s, min(e, cs)}, {max(s, ce), e}], fn {a, b} -> a >= b end)
    end)
  end

  @doc "Moves notes by `semitones`, spelled to suit the key."
  @spec transpose_chromatic(Score.t(), Context.t(), [id()], integer()) :: result()
  def transpose_chromatic(%Score{} = score, %Context{} = ctx, ids, semitones)
      when is_integer(semitones) do
    map_selected(score, ctx, ids, fn entry ->
      note_only(entry, fn note ->
        {step, alter} = Pitch.spell(Note.midi(note) + semitones, ctx.sf)
        %{note | step: step, alter: alter}
      end)
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
    map_selected(score, ctx, ids, fn entry ->
      note_only(entry, fn note ->
        {step, alter} = Pitch.transpose(note.step, note.alter, steps, semitones, ctx.sf)
        %{note | step: step, alter: alter}
      end)
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

    case Enum.filter(entries, &(&1.event.id in ids)) do
      [] ->
        {:ok, score}

      selected ->
        span = span(selected)
        flipped = flipped(selected, ids)
        rebuild(score, ctx, Enum.map(entries, &mirror(&1, ids, span, flipped)))
    end
  end

  # First tick plus last tick of the events: a start `s` mirrors to `span - s`.
  defp span(entries) do
    first = Enum.min_by(entries, & &1.start).start
    last = Enum.max(Enum.map(entries, &(&1.start + &1.ticks)))
    first + last
  end

  # Selected tie targets => the note now tied to them, reversed.
  defp flipped(selected, ids) do
    for %{event: %Note{id: from, tie_to: to}} <- selected, to in ids, into: %{}, do: {to, from}
  end

  defp mirror(entry, ids, span, flipped) do
    if entry.event.id in ids do
      %{
        entry
        | start: span - (entry.start + entry.ticks),
          event: put_tie(entry.event, flipped[entry.event.id])
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
  @spec split(Score.t(), Context.t(), id() | [id()]) ::
          {:ok, Score.t(), [id()]} | {:error, reason()}
  def split(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, [first | _] = chosen} <- find_entries(entries, ids),
         {:ok, head, tail} <- halves(first.event.value, first.event.dots),
         pieces = Map.new(chosen, &{&1.event.id, split_entry(&1, head, tail)}),
         {:ok, score} <-
           rebuild(score, ctx, Enum.flat_map(entries, &Map.get(pieces, &1.event.id, [&1]))) do
      {:ok, score, for(entry <- chosen, piece <- pieces[entry.event.id], do: piece.event.id)}
    end
  end

  def split(%Score{} = score, %Context{} = ctx, id), do: split(score, ctx, [id])

  defp split_entry(entry, {head_value, head_dots}, {tail_value, tail_dots}) do
    second = Ecto.UUID.generate()
    head_ticks = Duration.ticks(head_value, head_dots)

    event = claim(entry.event)

    head = %{
      entry
      | ticks: head_ticks,
        event: put_tie(%{event | value: head_value, dots: head_dots}, second)
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

    case find_entry(entries, id) do
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

    case find_entry(entries, id) do
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
            alter: Pitch.key_alter(ctx.sf, Pitch.letter(step)),
            tie_to: nil
        }

        with {:ok, score} <- add(score, ctx, [%{edge | event: note}]), do: {:ok, score, note.id}

      {:ok, _rest} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  defp same_chord?(
         %{kind: :note, start: start, ticks: ticks, event: %{staff: staff, voice: voice}},
         %{kind: :note, start: start, ticks: ticks, event: %{staff: staff, voice: voice}}
       ) do
    true
  end

  defp same_chord?(_entry, _other), do: false

  defp find_entries(entries, ids) do
    case Enum.filter(entries, &(&1.event.id in ids)) do
      [] -> {:error, :not_found}
      found -> {:ok, found}
    end
  end

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
  @spec set_value(Score.t(), Context.t(), id() | [id()], Duration.value(), 0..2) :: result()
  def set_value(%Score{} = score, %Context{} = ctx, id, value, dots) when not is_list(id) do
    set_value(score, ctx, [id], value, dots)
  end

  def set_value(_score, _ctx, _ids, value, _dots) when value not in @values do
    {:error, :unrepresentable}
  end

  def set_value(%Score{} = score, %Context{} = ctx, ids, value, dots) when dots in 0..2 do
    entries = Timeline.flatten(score, ctx)
    ticks = Duration.ticks(value, dots)

    with {:ok, [first | _] = chosen} <- find_entries(entries, ids),
         :ok <- fits_bar(Timeline.bars(score, ctx), first.start, ticks) do
      changed =
        Map.new(chosen, fn entry ->
          {entry.event.id,
           %{entry | ticks: ticks, event: claim(%{entry.event | value: value, dots: dots})}}
        end)

      rebuild(score, ctx, Enum.map(entries, &Map.get(changed, &1.event.id, &1)))
    end
  end

  defp fits_bar(bars, start, ticks) do
    bars
    |> bar_of(start)
    |> within_bar(start, ticks)
  end

  defp within_bar({bar_start, capacity}, start, ticks)
       when start + ticks <= bar_start + capacity do
    :ok
  end

  defp within_bar(_bar, _start, _ticks), do: {:error, :measure_full}

  @doc """
  Turns a note (or, given a chord's ids, the whole chord) into one rest of
  the same length and position, keeping the first note's id; ties into or
  out of it are removed.
  """
  @spec to_rest(Score.t(), Context.t(), id() | [id()]) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def to_rest(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, [%{event: %{id: first_id}} = first | _]} <- find_entries(entries, ids),
         others = Enum.reject(ids, &(&1 == first_id)),
         replaced =
           entries
           |> replace_entry(first_id, [%{first | kind: :rest, event: rest_from(first.event)}])
           |> Enum.reject(&(&1.event.id in others)),
         {:ok, score} <- rebuild(score, ctx, replaced) do
      {:ok, score, first_id}
    end
  end

  def to_rest(%Score{} = score, %Context{} = ctx, id), do: to_rest(score, ctx, [id])

  defp rest_from(event) do
    %Rest{
      id: event.id,
      staff: event.staff,
      voice: event.voice,
      offset: event.offset,
      value: event.value,
      dots: event.dots
    }
  end

  @doc """
  Turns a rest into a note of the same length and position (keeping its
  id), on `step` with `alter`.
  """
  @spec to_note(Score.t(), Context.t(), id(), integer(), -2..2) ::
          {:ok, Score.t(), id()} | {:error, reason()}
  def to_note(%Score{} = score, %Context{} = ctx, id, step, alter) when alter in -2..2 do
    entries = Timeline.flatten(score, ctx)

    with {:ok, entry} <- find_entry(entries, id),
         note_entry = %{entry | kind: :note, event: note_from(entry.event, step, alter)},
         {:ok, score} <- rebuild(score, ctx, replace_entry(entries, id, [note_entry])) do
      {:ok, score, id}
    end
  end

  defp note_from(event, step, alter) do
    %Note{
      id: event.id,
      staff: event.staff,
      voice: event.voice,
      offset: event.offset,
      value: event.value,
      dots: event.dots,
      step: step,
      alter: alter
    }
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
      |> Enum.map(&chord_key/1)
      |> Enum.uniq()

    with {:ok, entries, new_ids} <- rebuild_chords(entries, chords, pitches_for),
         {:ok, score} <- rebuild(score, ctx, entries) do
      {:ok, score, new_ids}
    end
  end

  defp chord_key(%{event: event, start: start}), do: {event.staff, event.voice, start}

  defp rebuild_chords(entries, chords, pitches_for) do
    Enum.reduce_while(chords, {:ok, entries, []}, fn key, {:ok, entries, new_ids} ->
      {old, kept} = Enum.split_with(entries, &(&1.kind == :note and chord_key(&1) == key))
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
    rebuild(Score.new(bars), to_ctx, merge_ties(Timeline.flatten(score, from_ctx)))
  end

  # How many bars of `ctx` it takes to reach tick `last` (at least one).
  defp bars_spanning(ctx, last) do
    bars_after(Context.capacity(ctx, 0), last, Context.measure_ticks(ctx))
  end

  defp bars_after(first, last, _bar) when last <= first, do: 1
  defp bars_after(first, last, bar), do: 1 + div(last - first + bar - 1, bar)

  defp find_entry(entries, id) do
    case Enum.find(entries, &(&1.event.id == id)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp replace_entry(entries, id, replacements) do
    Enum.flat_map(entries, fn
      %{event: %{id: ^id}} -> replacements
      entry -> [entry]
    end)
  end

  # Head up to `at` (keeping the id), tail moved `gap` later with a fresh id
  # and whatever tie the event had.
  defp split_at(entry, at, gap) do
    head = %{entry | ticks: at - entry.start, event: put_tie(entry.event, nil)}

    tail = %{
      entry
      | start: at + gap,
        ticks: entry.start + entry.ticks - at,
        event: %{entry.event | id: Ecto.UUID.generate()}
    }

    [head, tail]
  end

  defp put_tie(%Note{} = note, target), do: %{note | tie_to: target}
  defp put_tie(event, _target), do: event

  defp note_only(%{kind: :note} = entry, fun), do: {:ok, %{entry | event: fun.(entry.event)}}
  defp note_only(entry, _fun), do: {:ok, entry}

  defp map_selected(score, ctx, ids, fun) do
    with {:ok, entries} <- map_entries(score, ctx, ids, fun), do: rebuild(score, ctx, entries)
  end

  defp map_entries(score, ctx, ids, fun) do
    ids = MapSet.new(ids)

    score
    |> Timeline.flatten(ctx)
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      entry
      |> apply_if_selected(ids, fun)
      |> collect(acc)
    end)
  end

  defp apply_if_selected(entry, ids, fun) do
    if entry.event.id in ids, do: fun.(entry), else: {:ok, entry}
  end

  defp collect({:ok, entry}, acc), do: {:cont, {:ok, [entry | acc]}}
  defp collect(error, _acc), do: {:halt, error}

  ## Ties

  @doc """
  Ties two notes, given in either order: the earlier is tied to the later.
  They must be on the same staff, sound the same pitch, and the later must
  start exactly where the earlier ends.
  """
  @spec tie(Score.t(), Context.t(), id(), id()) :: result()
  def tie(%Score{} = score, %Context{} = ctx, id_a, id_b) do
    notes = note_entries(score, ctx)

    with {:ok, a} <- fetch(notes, id_a),
         {:ok, b} <- fetch(notes, id_b),
         [first, second] = Enum.sort_by([a, b], & &1.start),
         :ok <- check_tieable(first, second) do
      {:ok, update_notes(score, &tie_note(&1, first.event.id, second.event.id))}
    end
  end

  @doc "Removes the ties into and out of a note."
  @spec untie(Score.t(), id()) :: Score.t()
  def untie(%Score{} = score, id) do
    update_notes(score, fn
      %Note{id: ^id} = note -> %{note | tie_to: nil}
      %Note{tie_to: ^id} = note -> %{note | tie_to: nil}
      note -> note
    end)
  end

  defp tie_note(%Note{id: id} = note, id, target), do: %{note | tie_to: target}
  defp tie_note(note, _id, _target), do: note

  defp check_tieable(first, second) do
    if tieable?(first, second), do: :ok, else: {:error, :not_tieable}
  end

  # Distinct notes on one staff, the same pitch, the second starting where
  # the first ends.
  defp tieable?(%{event: %{id: id}}, %{event: %{id: id}}), do: false

  defp tieable?(%{event: %{staff: staff}} = first, %{event: %{staff: staff}} = second) do
    Note.midi(first.event) == Note.midi(second.event) and
      first.start + first.ticks == second.start
  end

  defp tieable?(_first, _second), do: false

  defp fetch(notes, id) do
    case Map.fetch(notes, id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  defp note_entries(score, ctx) do
    for %{kind: :note} = entry <- Timeline.flatten(score, ctx), into: %{} do
      {entry.event.id, entry}
    end
  end

  # Drops ties that no longer join a note to the same pitch right after it.
  defp prune_ties(score, ctx) do
    notes = note_entries(score, ctx)

    update_notes(score, fn
      %Note{tie_to: nil} = note -> note
      note -> keep_tie(note, notes[note.id], Map.get(notes, note.tie_to))
    end)
  end

  defp keep_tie(note, _entry, nil = _target), do: %{note | tie_to: nil}

  defp keep_tie(note, entry, target) do
    if tieable?(entry, target), do: note, else: %{note | tie_to: nil}
  end

  defp update_notes(%Score{measures: measures} = score, fun) do
    %{score | measures: Enum.map(measures, fn m -> %{m | notes: Enum.map(m.notes, fun)} end)}
  end

  ## Measures

  @doc "Inserts an empty measure before `index` (`index == length` appends)."
  @spec insert_measure(Score.t(), non_neg_integer()) :: result()
  @spec insert_measure(Score.t(), Context.t(), non_neg_integer()) :: result()
  def insert_measure(%Score{measures: measures} = score, index)
      when is_integer(index) and index >= 0 and index <= length(measures) do
    {:ok, %{score | measures: List.insert_at(measures, index, Measure.new())}}
  end

  def insert_measure(_score, _index), do: {:error, :no_such_measure}

  @doc """
  Inserts a measure of filler rests before `index`, dropping ties the new
  bar separates.
  """
  def insert_measure(%Score{} = score, %Context{} = ctx, index) do
    with {:ok, score} <- insert_measure(score, index) do
      {:ok, score |> prune_ties(ctx) |> fill_rests(ctx)}
    end
  end

  @doc "Appends an empty measure."
  @spec append_measure(Score.t()) :: result()
  def append_measure(%Score{measures: measures} = score) do
    insert_measure(score, length(measures))
  end

  @doc "Appends a measure of filler rests."
  @spec append_measure(Score.t(), Context.t()) :: result()
  def append_measure(%Score{measures: measures} = score, %Context{} = ctx) do
    insert_measure(score, ctx, length(measures))
  end

  @doc """
  Deletes measure `index` and its contents. The last measure cannot be
  deleted, nor the pickup bar (remove the pickup in the settings instead).
  """
  @spec delete_measure(Score.t(), Context.t(), non_neg_integer()) :: result()
  def delete_measure(%Score{measures: [_only]}, _ctx, 0), do: {:error, :last_measure}

  def delete_measure(%Score{}, %Context{pickup_ticks: pickup}, 0) when pickup > 0 do
    {:error, :pickup_bar}
  end

  def delete_measure(%Score{measures: measures} = score, ctx, index)
      when is_integer(index) and index >= 0 and index < length(measures) do
    {:ok, prune_ties(%{score | measures: List.delete_at(measures, index)}, ctx)}
  end

  def delete_measure(_score, _ctx, _index), do: {:error, :no_such_measure}

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
        not filler?(entry) or entry.start + entry.ticks <= to do
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
    selected = Enum.filter(Timeline.flatten(score, ctx), &(&1.event.id in ids))

    origin =
      selected
      |> Enum.map(& &1.start)
      |> Enum.min(fn -> 0 end)

    %Clipboard{
      entries:
        Enum.map(selected, fn entry ->
          %{entry | start: entry.start - origin, event: drop_outside_tie(entry.event, ids)}
        end)
    }
  end

  defp drop_outside_tie(%Note{tie_to: target} = note, ids) when not is_nil(target) do
    if target in ids, do: note, else: %{note | tie_to: nil}
  end

  defp drop_outside_tie(event, _ids), do: event

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
        event = renumber(%{claim(entry.event) | id: fresh[entry.event.id]}, fresh)
        %{entry | start: entry.start + at, event: event}
      end)

    entries = merge_ties(clear_rests_under(Timeline.flatten(score, ctx), pasted) ++ pasted)

    with {:ok, score} <- rebuild(score, ctx, entries), do: {:ok, score, Map.values(fresh)}
  end

  defp renumber(%Note{tie_to: target} = note, fresh) when not is_nil(target) do
    %{note | tie_to: fresh[target]}
  end

  defp renumber(event, _fresh), do: event

  ## Rests

  @doc """
  Rewrites the filler rests: every gap in voice 1 of each staff, and in any
  other voice that has notes in the measure, is filled with rests on the
  beats (see `DrawMusic.Music.Gaps`). A filler rest that comes out the same
  as before keeps its id.
  """
  @spec fill_rests(Score.t(), Context.t()) :: Score.t()
  def fill_rests(%Score{} = score, %Context{} = ctx) do
    refill(score, ctx, filler_ids(score))
  end

  defp refill(%Score{measures: measures} = score, ctx, old_ids) do
    filled =
      measures
      |> Enum.zip(Timeline.bars(score, ctx))
      |> Enum.map(fn {measure, {_start, capacity}} ->
        kept = Enum.reject(measure.rests, & &1.filler)

        fillers =
          %{measure | rests: kept}
          |> Gaps.rests(capacity)
          |> Enum.map(fn rest ->
            %{rest | id: Map.get_lazy(old_ids, filler_key(measure, rest), &Ecto.UUID.generate/0)}
          end)

        %{measure | rests: Enum.sort_by(kept ++ fillers, &{&1.offset, &1.staff, &1.voice})}
      end)

    %{score | measures: filled}
  end

  defp filler_ids(score) do
    for measure <- score.measures, %Rest{filler: true} = rest <- measure.rests, into: %{} do
      {filler_key(measure, rest), rest.id}
    end
  end

  defp filler_key(measure, rest) do
    {measure.id, rest.staff, rest.voice, rest.offset, rest.value, rest.dots}
  end

  defp filler?(%{event: %Rest{filler: true}}), do: true
  defp filler?(_entry), do: false

  # An edited rest is the user's: it is no longer rewritten as filler.
  defp claim(%Rest{} = rest), do: %{rest | filler: false}
  defp claim(event), do: event

  # Tied pieces of a lone note (no chord partner in its voice) that follow
  # one another become one entry, keeping the first piece's id; rebarring
  # splits it again only where bar lines and note values need it.
  defp merge_ties(entries) do
    notes = for %{kind: :note} = entry <- entries, into: %{}, do: {entry.event.id, entry}
    sizes = notes |> Map.values() |> Enum.frequencies_by(&chord_key/1)
    lone? = &(sizes[chord_key(&1)] == 1)

    links =
      notes
      |> Map.values()
      |> Enum.flat_map(fn entry ->
        case Map.get(notes, entry.event.tie_to) do
          nil -> []
          target -> mergeable(entry, target, lone?)
        end
      end)
      |> Map.new()

    absorbed = MapSet.new(Map.values(links), & &1.event.id)

    entries
    |> Enum.reject(&(&1.event.id in absorbed))
    |> Enum.map(&extend(&1, links))
  end

  defp mergeable(entry, target, lone?) do
    if entry.event.voice == target.event.voice and lone?.(entry) and lone?.(target) and
         tieable?(entry, target) do
      [{entry.event.id, target}]
    else
      []
    end
  end

  defp extend(entry, links) do
    case Map.get(links, entry.event.id) do
      nil ->
        entry

      next ->
        merged = extend(next, links)

        %{
          entry
          | ticks: entry.ticks + merged.ticks,
            event: put_tie(entry.event, merged.event.tie_to)
        }
    end
  end

  ## Rebuilding

  # New notes take the place of the rests they cover in their voice.
  defp add(score, ctx, new_entries) do
    rebuild(
      score,
      ctx,
      clear_rests_under(Timeline.flatten(score, ctx), new_entries) ++ new_entries
    )
  end

  defp clear_rests_under(entries, new_entries) do
    notes = Enum.filter(new_entries, &(&1.kind == :note))

    Enum.reject(entries, fn entry ->
      entry.kind == :rest and Enum.any?(notes, &overlapping_in_voice?(&1, entry))
    end)
  end

  defp overlapping_in_voice?(a, b) do
    a.event.staff == b.event.staff and a.event.voice == b.event.voice and
      a.start < b.start + b.ticks and b.start < a.start + a.ticks
  end

  # Filler is dropped and written afresh once the events are in their bars.
  defp rebuild(score, ctx, entries) do
    entries = Enum.reject(entries, &filler?/1)

    with :ok <- check_layout(entries),
         {:ok, rebarred} <- Timeline.rebar(score, ctx, entries) do
      {:ok, rebarred |> prune_ties(ctx) |> refill(ctx, filler_ids(score))}
    end
  end

  defp check_layout(entries) do
    with :ok <- check_range(entries) do
      entries
      |> Enum.group_by(&{&1.event.staff, &1.event.voice})
      |> Enum.reduce_while(:ok, fn {_staff_voice, voice_entries}, :ok ->
        voice_entries
        |> Enum.sort_by(& &1.start)
        |> check_voice()
        |> continue_if_ok()
      end)
    end
  end

  defp continue_if_ok(:ok), do: {:cont, :ok}
  defp continue_if_ok(error), do: {:halt, error}

  defp check_range(entries) do
    case Enum.reject(entries, &in_range?/1) do
      [] -> :ok
      _out_of_range -> {:error, :out_of_range}
    end
  end

  defp in_range?(%{kind: :note, event: note}), do: Pitch.playable?(note.step, note.alter)

  defp in_range?(_entry), do: true

  # Entries of one voice, sorted by start; compare each with the ones that
  # begin before it ends.
  defp check_voice([]), do: :ok

  defp check_voice([entry | rest]) do
    rest
    |> Enum.take_while(&(&1.start < entry.start + entry.ticks))
    |> Enum.reduce_while(:ok, fn other, :ok ->
      entry
      |> collision(other)
      |> continue_if_ok()
    end)
    |> case do
      :ok -> check_voice(rest)
      error -> error
    end
  end

  # Notes starting together with the same length form a chord, unless they
  # share a step.
  defp collision(
         %{kind: :note, start: start, ticks: ticks, event: %{step: step}},
         %{kind: :note, start: start, ticks: ticks, event: %{step: step}}
       ) do
    {:error, :duplicate}
  end

  defp collision(
         %{kind: :note, start: start, ticks: ticks},
         %{kind: :note, start: start, ticks: ticks}
       ) do
    :ok
  end

  defp collision(_a, _b), do: {:error, :overlap}

  defp bar_of(bars, tick) do
    Enum.find(bars, fn {start, capacity} -> tick >= start and tick < start + capacity end)
  end
end
