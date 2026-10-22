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
      edits that break a tie remove it.

  Error reasons: `:no_such_measure`, `:measure_full`, `:overlap`,
  `:duplicate`, `:out_of_range`, `:before_start`, `:not_found`,
  `:not_tieable`, `:last_measure`, `:unrepresentable`.
  """

  alias DrawMusic.Music.{Context, Duration, Measure, Note, Pitch, Rest, Score, Timeline}

  ## Placing

  @doc """
  Places a note in measure `index`. `attrs`: `staff`, `offset` (ticks into
  the measure), `value`, optional `dots`, `step`, optional `alter`, optional
  `voice`. Without a voice, the note goes in the lowest voice it fits.
  """
  def place_note(%Score{} = score, %Context{} = ctx, index, attrs) do
    with {:ok, score, [note]} <-
           place(
             score,
             ctx,
             index,
             attrs,
             &[new_note(attrs, &1, attrs.step, Map.get(attrs, :alter, 0))]
           ) do
      {:ok, score, note.id}
    end
  end

  @doc """
  Places a chord: one note per `{step, alter}` in `pitches`, all at the same
  position and length, in one voice. `attrs` as for `place_note/4`, without
  step/alter.
  """
  def place_chord(%Score{} = score, %Context{} = ctx, index, attrs, pitches) do
    build = fn voice ->
      Enum.map(pitches, fn {step, alter} -> new_note(attrs, voice, step, alter) end)
    end

    with {:ok, score, notes} <- place(score, ctx, index, attrs, build) do
      {:ok, score, Enum.map(notes, & &1.id)}
    end
  end

  @doc """
  Places a rest in measure `index`. `attrs`: `staff`, `offset`, `value`,
  optional `dots`, optional `voice` (else the lowest voice it fits).
  """
  def place_rest(%Score{} = score, %Context{} = ctx, index, attrs) do
    build = fn voice ->
      [
        %Rest{
          id: Ecto.UUID.generate(),
          staff: attrs.staff,
          voice: voice,
          offset: attrs.offset,
          value: attrs.value,
          dots: Map.get(attrs, :dots, 0)
        }
      ]
    end

    with {:ok, score, [rest]} <- place(score, ctx, index, attrs, build) do
      {:ok, score, rest.id}
    end
  end

  # Tries the requested voice, or voices 1..4 in turn; returns the first
  # success or the first voice's error.
  defp place(score, ctx, index, attrs, build) do
    voices = if Map.has_key?(attrs, :voice), do: [attrs.voice], else: [1, 2, 3, 4]

    Enum.reduce_while(voices, nil, fn voice, first_error ->
      events = build.(voice)

      case place_events(score, ctx, index, events) do
        {:ok, score} -> {:halt, {:ok, score, events}}
        error -> {:cont, first_error || error}
      end
    end)
  end

  defp place_events(score, ctx, index, [first | _] = events) do
    with {:ok, start} <- locate(score, ctx, index, first) do
      add(score, ctx, Enum.map(events, &%{Timeline.entry(&1, 0) | start: start}))
    end
  end

  defp new_note(attrs, voice, step, alter) do
    %Note{
      id: Ecto.UUID.generate(),
      staff: attrs.staff,
      voice: voice,
      offset: attrs.offset,
      value: attrs.value,
      dots: Map.get(attrs, :dots, 0),
      step: step,
      alter: alter
    }
  end

  defp locate(score, ctx, index, event) when is_integer(index) and index >= 0 do
    case Enum.at(Timeline.bars(score, ctx), index) do
      nil ->
        {:error, :no_such_measure}

      {start, capacity} ->
        if event.offset >= 0 and
             event.offset + Duration.ticks(event.value, event.dots) <= capacity,
           do: {:ok, start + event.offset},
           else: {:error, :measure_full}
    end
  end

  defp locate(_score, _ctx, _index, _event), do: {:error, :no_such_measure}

  ## Changing selected events

  @doc "Removes the notes and rests with the given ids."
  def remove(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    rebuild(score, ctx, Enum.reject(Timeline.flatten(score, ctx), &(&1.event.id in ids)))
  end

  @doc """
  Sets the dots of the given events. The result must still fit in each
  event's measure (`:measure_full`); dot a whole chord together.
  """
  def set_dots(%Score{} = score, %Context{} = ctx, ids, dots) when dots in 0..2 do
    bars = Timeline.bars(score, ctx)

    map_selected(score, ctx, ids, fn entry ->
      ticks = Duration.ticks(entry.event.value, dots)
      {bar_start, capacity} = bar_of(bars, entry.start)

      if entry.start + ticks <= bar_start + capacity,
        do: {:ok, %{entry | ticks: ticks, event: %{entry.event | dots: dots}}},
        else: {:error, :measure_full}
    end)
  end

  @doc "Sets the absolute alteration (-2..2) of the given notes."
  def set_alter(%Score{} = score, %Context{} = ctx, ids, alter) when alter in -2..2 do
    map_selected(score, ctx, ids, &note_only(&1, fn note -> %{note | alter: alter} end))
  end

  @doc """
  Moves the given notes `delta` steps up (positive) or down the scale of the
  key: each lands on the key's own version of its new letter.
  """
  def move_steps(%Score{} = score, %Context{} = ctx, ids, delta) when is_integer(delta) do
    map_selected(score, ctx, ids, fn entry ->
      note_only(entry, fn note ->
        step = note.step + delta
        %{note | step: step, alter: Pitch.key_alter(ctx.sf, Pitch.letter(step))}
      end)
    end)
  end

  @doc """
  Moves the given events `beats` time-signature units later (positive) or
  earlier. Events crossing a bar line are split into tied notes; measures
  are appended when needed.
  """
  def shift(%Score{} = score, %Context{} = ctx, ids, beats) when is_integer(beats) do
    delta = beats * Context.beat_ticks(ctx)
    map_selected(score, ctx, ids, fn entry -> {:ok, %{entry | start: entry.start + delta}} end)
  end

  @doc """
  Inserts `ticks` of time at absolute tick `at` on one staff: every event on
  `staff` starting at or after `at` moves right by `ticks`. An event sounding
  across `at` is split there and its tail moves; the tie between a note's
  halves is dropped, since they no longer touch. Bars are appended as
  needed; the other staff is untouched.
  """
  def insert_time(%Score{} = score, %Context{} = ctx, at, ticks, staff)
      when is_integer(at) and at >= 0 and is_integer(ticks) and ticks > 0 do
    entries =
      score
      |> Timeline.flatten(ctx)
      |> Enum.flat_map(fn
        %{event: %{staff: ^staff}} = entry when entry.start >= at ->
          [%{entry | start: entry.start + ticks}]

        %{event: %{staff: ^staff}} = entry when entry.start + entry.ticks > at ->
          split_at(entry, at, ticks)

        entry ->
          [entry]
      end)

    rebuild(score, ctx, entries)
  end

  @doc """
  Deletes events and closes the gap on each staff they were on: every
  later event on that staff moves left by the time emptied before it. Time
  another voice on the staff still sounds is not a gap.
  """
  def delete(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    {gone, kept} = score |> Timeline.flatten(ctx) |> Enum.split_with(&(&1.event.id in ids))

    gaps =
      gone
      |> Enum.group_by(& &1.event.staff)
      |> Map.new(fn {staff, removed} ->
        {staff, emptied(removed, Enum.filter(kept, &(&1.event.staff == staff)))}
      end)

    shifted =
      Enum.map(kept, fn entry ->
        closed =
          for {from, to} <- Map.get(gaps, entry.event.staff, []), to <= entry.start, do: to - from

        %{entry | start: entry.start - Enum.sum(closed)}
      end)

    rebuild(score, ctx, shifted)
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
  def transpose_interval(%Score{} = score, %Context{} = ctx, ids, steps, semitones)
      when is_integer(steps) and is_integer(semitones) do
    map_selected(score, ctx, ids, fn entry ->
      note_only(entry, &by_interval(&1, steps, semitones, ctx.sf))
    end)
  end

  defp by_interval(note, steps, semitones, sf) do
    midi = Note.midi(note) + semitones
    step = note.step + steps
    {step, alter} = spelled(step, midi - Pitch.natural_midi(step), midi, sf)
    %{note | step: step, alter: alter}
  end

  defp spelled(step, alter, _midi, _sf) when alter in -2..2, do: {step, alter}
  defp spelled(_step, _alter, midi, sf), do: Pitch.spell(midi, sf)

  @doc """
  Plays the events backwards within the time they span. Ties inside the
  selection are flipped so they still point forward; ties into or out of
  it are dropped.
  """
  def reverse(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    entries = Timeline.flatten(score, ctx)
    selected = Enum.filter(entries, &(&1.event.id in ids))

    if selected == [] do
      {:ok, score}
    else
      first = selected |> Enum.map(& &1.start) |> Enum.min()
      last = selected |> Enum.map(&(&1.start + &1.ticks)) |> Enum.max()

      flipped =
        for %{event: %Note{id: from, tie_to: to}} <- selected,
            to in ids,
            into: %{},
            do: {to, from}

      entries
      |> Enum.map(&mirror(&1, ids, first + last, flipped))
      |> then(&rebuild(score, ctx, &1))
    end
  end

  # A selected entry's start mirrored within the span (`span` = first +
  # last tick), with its tie flipped.
  defp mirror(entry, ids, span, flipped) do
    if entry.event.id in ids,
      do: %{
        entry
        | start: span - (entry.start + entry.ticks),
          event: put_tie(entry.event, flipped[entry.event.id])
      },
      else: entry
  end

  @doc """
  Splits a note or rest into two. An undotted value becomes two of the next
  shorter value; a dotted one becomes the same value with one dot fewer plus
  the remainder (dotted quarter → quarter + eighth). A note's halves are tied.
  Returns the ids of the halves, head then tail for each event; heads keep
  the events' ids. Give the ids of a whole chord (see `chord_ids/3`) to
  split it together.
  """
  def split(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, chosen} <- find_entries(entries, ids),
         {:ok, head_value_dots, tail_value_dots} <-
           halves(hd(chosen).event.value, hd(chosen).event.dots) do
      pieces = Map.new(chosen, &{&1.event.id, split_entry(&1, head_value_dots, tail_value_dots)})

      replaced =
        Enum.flat_map(entries, fn entry -> Map.get(pieces, entry.event.id, [entry]) end)

      new_ids = for entry <- chosen, piece <- pieces[entry.event.id], do: piece.event.id
      with {:ok, score} <- rebuild(score, ctx, replaced), do: {:ok, score, new_ids}
    end
  end

  def split(%Score{} = score, %Context{} = ctx, id), do: split(score, ctx, [id])

  defp split_entry(entry, {head_value, head_dots}, {tail_value, tail_dots}) do
    second = Ecto.UUID.generate()
    head_ticks = Duration.ticks(head_value, head_dots)

    head = %{
      entry
      | ticks: head_ticks,
        event: put_tie(%{entry.event | value: head_value, dots: head_dots}, second)
    }

    tail = %{
      entry
      | start: entry.start + head_ticks,
        ticks: entry.ticks - head_ticks,
        event: %{entry.event | id: second, value: tail_value, dots: tail_dots}
    }

    [head, tail]
  end

  @doc """
  Ids of the chord `id` belongs to: the notes of its staff and voice that
  start and end with it (just `[id]` for a rest or a lone note).
  """
  def chord_ids(%Score{} = score, %Context{} = ctx, id) do
    entries = Timeline.flatten(score, ctx)

    case find_entry(entries, id) do
      {:ok, %{kind: :note} = entry} ->
        for %{kind: :note} = other <- entries,
            other.event.staff == entry.event.staff and other.event.voice == entry.event.voice,
            other.start == entry.start and other.ticks == entry.ticks,
            do: other.event.id

      _rest_or_missing ->
        [id]
    end
  end

  defp find_entries(entries, ids) do
    case Enum.filter(entries, &(&1.event.id in ids)) do
      [] -> {:error, :not_found}
      found -> {:ok, found}
    end
  end

  defp halves(value, 0) do
    case Enum.drop_while(Duration.values(), &(&1 != value)) do
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
  def set_value(%Score{} = score, %Context{} = ctx, ids, value, dots)
      when is_list(ids) and dots in 0..2 do
    entries = Timeline.flatten(score, ctx)

    with true <- value in Duration.values() || {:error, :unrepresentable},
         {:ok, [first | _] = chosen} <- find_entries(entries, ids),
         ticks = Duration.ticks(value, dots),
         :ok <- fits_bar(score, ctx, first.start, ticks) do
      changed =
        Map.new(chosen, fn entry ->
          {entry.event.id,
           %{entry | ticks: ticks, event: %{entry.event | value: value, dots: dots}}}
        end)

      rebuild(score, ctx, Enum.map(entries, &Map.get(changed, &1.event.id, &1)))
    end
  end

  def set_value(%Score{} = score, %Context{} = ctx, id, value, dots),
    do: set_value(score, ctx, [id], value, dots)

  defp fits_bar(score, ctx, start, ticks) do
    {bar_start, capacity} = bar_of(Timeline.bars(score, ctx), start)
    if start + ticks <= bar_start + capacity, do: :ok, else: {:error, :measure_full}
  end

  @doc """
  Turns a note (or, given a chord's ids, the whole chord) into one rest of
  the same length and position, keeping the first note's id; ties into or
  out of it are removed.
  """
  def to_rest(%Score{} = score, %Context{} = ctx, ids) when is_list(ids) do
    entries = Timeline.flatten(score, ctx)

    with {:ok, [first | _]} <- find_entries(entries, ids) do
      rest = %Rest{
        id: first.event.id,
        staff: first.event.staff,
        voice: first.event.voice,
        offset: first.event.offset,
        value: first.event.value,
        dots: first.event.dots
      }

      replaced =
        Enum.flat_map(entries, fn entry ->
          cond do
            entry.event.id == first.event.id -> [%{entry | kind: :rest, event: rest}]
            entry.event.id in ids -> []
            true -> [entry]
          end
        end)

      with {:ok, score} <- rebuild(score, ctx, replaced), do: {:ok, score, first.event.id}
    end
  end

  def to_rest(%Score{} = score, %Context{} = ctx, id), do: to_rest(score, ctx, [id])

  @doc """
  Turns a rest into a note of the same length and position (keeping its
  id), on `step` with `alter`.
  """
  def to_note(%Score{} = score, %Context{} = ctx, id, step, alter) when alter in -2..2 do
    entries = Timeline.flatten(score, ctx)

    with {:ok, entry} <- find_entry(entries, id) do
      note = %Note{
        id: id,
        staff: entry.event.staff,
        voice: entry.event.voice,
        offset: entry.event.offset,
        value: entry.event.value,
        dots: entry.event.dots,
        step: step,
        alter: alter
      }

      with {:ok, score} <-
             rebuild(
               score,
               ctx,
               replace_entry(entries, id, [%{entry | kind: :note, event: note}])
             ),
           do: {:ok, score, id}
    end
  end

  @doc """
  Re-reads a score written against `from_ctx` into the bars of `to_ctx`
  (after a time signature or pickup change): every event keeps its time
  from the start, events crossing the new bar lines are split into ties,
  and the score keeps at least as many bars as the music spanned.
  """
  def rebar_to(%Score{} = score, %Context{} = from_ctx, %Context{} = to_ctx) do
    empty = %Score{
      measures:
        for(_ <- 1..bars_spanning(to_ctx, Timeline.end_tick(score, from_ctx)), do: Measure.new())
    }

    rebuild(empty, to_ctx, Timeline.flatten(score, from_ctx))
  end

  # How many bars of `ctx` it takes to reach tick `last` (at least one).
  defp bars_spanning(ctx, last) do
    first = Context.capacity(ctx, 0)

    if last <= first,
      do: 1,
      else: 1 + div(last - first + Context.measure_ticks(ctx) - 1, Context.measure_ticks(ctx))
  end

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
    ids = MapSet.new(ids)

    score
    |> Timeline.flatten(ctx)
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      entry |> apply_if_selected(ids, fun) |> collect(acc)
    end)
    |> case do
      {:ok, entries} -> rebuild(score, ctx, entries)
      error -> error
    end
  end

  defp apply_if_selected(entry, ids, fun),
    do: if(entry.event.id in ids, do: fun.(entry), else: {:ok, entry})

  defp collect({:ok, entry}, acc), do: {:cont, {:ok, [entry | acc]}}
  defp collect(error, _acc), do: {:halt, error}

  ## Ties

  @doc """
  Ties two notes, given in either order: the earlier is tied to the later.
  They must be on the same staff, sound the same pitch, and the later must
  start exactly where the earlier ends.
  """
  def tie(%Score{} = score, %Context{} = ctx, id_a, id_b) do
    notes = note_entries(score, ctx)

    with {:ok, a} <- fetch(notes, id_a),
         {:ok, b} <- fetch(notes, id_b) do
      [first, second] = Enum.sort_by([a, b], & &1.start)

      if tieable?(first, second),
        do: {:ok, update_notes(score, &tie_note(&1, first.event.id, second.event.id))},
        else: {:error, :not_tieable}
    end
  end

  @doc "Removes the ties into and out of a note."
  def untie(%Score{} = score, id) do
    update_notes(score, fn
      %Note{id: ^id} = note -> %{note | tie_to: nil}
      %Note{tie_to: ^id} = note -> %{note | tie_to: nil}
      note -> note
    end)
  end

  defp tie_note(%Note{id: id} = note, id, target), do: %{note | tie_to: target}
  defp tie_note(note, _id, _target), do: note

  defp tieable?(first, second) do
    first.event.id != second.event.id and first.event.staff == second.event.staff and
      Note.midi(first.event) == Note.midi(second.event) and
      first.start + first.ticks == second.start
  end

  defp fetch(notes, id) do
    case Map.fetch(notes, id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  defp note_entries(score, ctx) do
    for %{kind: :note} = entry <- Timeline.flatten(score, ctx),
        into: %{},
        do: {entry.event.id, entry}
  end

  # Drops ties that no longer join a note to the same pitch right after it.
  defp prune_ties(score, ctx) do
    notes = note_entries(score, ctx)

    update_notes(score, fn
      %Note{tie_to: nil} = note ->
        note

      note ->
        target = Map.get(notes, note.tie_to)
        if target && tieable?(notes[note.id], target), do: note, else: %{note | tie_to: nil}
    end)
  end

  defp update_notes(%Score{measures: measures} = score, fun) do
    %{score | measures: Enum.map(measures, fn m -> %{m | notes: Enum.map(m.notes, fun)} end)}
  end

  ## Measures

  @doc "Inserts an empty measure before `index` (`index == length` appends)."
  def insert_measure(%Score{measures: measures} = score, index)
      when is_integer(index) and index >= 0 and index <= length(measures),
      do: {:ok, %{score | measures: List.insert_at(measures, index, Measure.new())}}

  def insert_measure(_score, _index), do: {:error, :no_such_measure}

  @doc "Inserts an empty measure before `index`, dropping ties the new bar separates."
  def insert_measure(%Score{} = score, %Context{} = ctx, index) do
    with {:ok, score} <- insert_measure(score, index), do: {:ok, prune_ties(score, ctx)}
  end

  @doc "Appends an empty measure."
  def append_measure(%Score{measures: measures} = score),
    do: insert_measure(score, length(measures))

  @doc """
  Deletes measure `index` and its contents. The last measure cannot be
  deleted, nor the pickup bar (remove the pickup in the settings instead).
  """
  def delete_measure(%Score{measures: [_only]}, _ctx, 0), do: {:error, :last_measure}

  def delete_measure(%Score{}, %Context{pickup_ticks: pickup}, 0) when pickup > 0,
    do: {:error, :pickup_bar}

  def delete_measure(%Score{measures: measures} = score, ctx, index)
      when is_integer(index) and index >= 0 and index < length(measures) do
    {:ok, prune_ties(%{score | measures: List.delete_at(measures, index)}, ctx)}
  end

  def delete_measure(_score, _ctx, _index), do: {:error, :no_such_measure}

  ## Selection and clipboard

  @doc "Ids of the events starting in ticks `from..to-1` on the given staves."
  def select_range(%Score{} = score, %Context{} = ctx, from, to, staves \\ [:treble, :bass]) do
    for entry <- Timeline.flatten(score, ctx),
        entry.start >= from and entry.start < to,
        entry.event.staff in staves,
        do: entry.event.id
  end

  @doc """
  Copies the given events. Positions are kept relative to the earliest
  one; ties to notes outside the selection are dropped.
  """
  def copy(%Score{} = score, %Context{} = ctx, ids) do
    ids = MapSet.new(ids)
    selected = Enum.filter(Timeline.flatten(score, ctx), &(&1.event.id in ids))
    origin = selected |> Enum.map(& &1.start) |> Enum.min(fn -> 0 end)

    %{
      entries:
        Enum.map(selected, fn entry ->
          %{entry | start: entry.start - origin, event: drop_outside_tie(entry.event, ids)}
        end)
    }
  end

  defp drop_outside_tie(%Note{tie_to: target} = note, ids) when not is_nil(target),
    do: if(target in ids, do: note, else: %{note | tie_to: nil})

  defp drop_outside_tie(event, _ids), do: event

  @doc """
  Pastes a clipboard from `copy/3` starting at absolute tick `at`, with
  fresh ids. Returns the new ids.
  """
  def paste(%Score{} = score, %Context{} = ctx, %{entries: entries}, at)
      when is_integer(at) and at >= 0 do
    fresh = Map.new(entries, &{&1.event.id, Ecto.UUID.generate()})

    pasted =
      Enum.map(entries, fn entry ->
        event = %{entry.event | id: fresh[entry.event.id]}

        event =
          case event do
            %Note{tie_to: target} when not is_nil(target) -> %{event | tie_to: fresh[target]}
            _ -> event
          end

        %{entry | start: entry.start + at, event: event}
      end)

    with {:ok, score} <- add(score, ctx, pasted), do: {:ok, score, Map.values(fresh)}
  end

  ## Rests

  @doc """
  Fills the gaps with rests: in voice 1 of each staff, and in any other voice
  that has notes in the measure.
  """
  def fill_rests(%Score{measures: measures} = score, %Context{} = ctx) do
    filled =
      measures
      |> Enum.zip(Timeline.bars(score, ctx))
      |> Enum.map(fn {measure, {_start, capacity}} ->
        rests =
          Enum.flat_map(voices_in(measure), &gap_rests(measure, &1, capacity)) ++ measure.rests

        %{measure | rests: Enum.sort_by(rests, &{&1.offset, &1.staff, &1.voice})}
      end)

    %{score | measures: filled}
  end

  defp voices_in(measure) do
    Enum.uniq([{:treble, 1}, {:bass, 1} | Enum.map(measure.notes, &{&1.staff, &1.voice})])
  end

  defp gap_rests(measure, {staff, voice}, capacity) do
    occupied =
      for event <- measure.notes ++ measure.rests, event.staff == staff, event.voice == voice do
        {event.offset, event.offset + Duration.ticks(event.value, event.dots)}
      end
      |> Enum.sort()

    {gaps, cursor} =
      Enum.reduce(occupied, {[], 0}, fn {from, to}, {gaps, cursor} ->
        gaps = if from > cursor, do: [{cursor, from - cursor} | gaps], else: gaps
        {gaps, max(cursor, to)}
      end)

    gaps = if capacity > cursor, do: [{cursor, capacity - cursor} | gaps], else: gaps
    Enum.flat_map(gaps, &rests_for_gap(&1, staff, voice))
  end

  defp rests_for_gap({offset, len}, staff, voice) do
    case Duration.decompose(len) do
      {:ok, values} ->
        values
        |> Enum.map_reduce(offset, fn {value, dots}, at ->
          rest = %Rest{
            id: Ecto.UUID.generate(),
            staff: staff,
            voice: voice,
            offset: at,
            value: value,
            dots: dots
          }

          {rest, at + Duration.ticks(value, dots)}
        end)
        |> elem(0)

      {:error, _reason} ->
        []
    end
  end

  ## Rebuilding

  defp add(score, ctx, new_entries),
    do: rebuild(score, ctx, Timeline.flatten(score, ctx) ++ new_entries)

  defp rebuild(score, ctx, entries) do
    with :ok <- check_layout(entries),
         {:ok, score} <- Timeline.rebar(score, ctx, entries) do
      {:ok, prune_ties(score, ctx)}
    end
  end

  defp check_layout(entries) do
    with :ok <- check_range(entries) do
      entries
      |> Enum.group_by(&{&1.event.staff, &1.event.voice})
      |> Enum.reduce_while(:ok, fn {_staff_voice, voice_entries}, :ok ->
        voice_entries |> Enum.sort_by(& &1.start) |> check_voice() |> continue_if_ok()
      end)
    end
  end

  defp continue_if_ok(:ok), do: {:cont, :ok}
  defp continue_if_ok(error), do: {:halt, error}

  defp check_range(entries) do
    if Enum.all?(entries, &in_range?/1), do: :ok, else: {:error, :out_of_range}
  end

  defp in_range?(%{kind: :note, event: note}),
    do: note.alter in -2..2 and Pitch.in_range?(Note.midi(note))

  defp in_range?(_entry), do: true

  # Entries of one voice, sorted by start; compare each with the ones that
  # begin before it ends.
  defp check_voice([]), do: :ok

  defp check_voice([entry | rest]) do
    rest
    |> Enum.take_while(&(&1.start < entry.start + entry.ticks))
    |> Enum.reduce_while(:ok, fn other, :ok ->
      case collision(entry, other) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
    |> case do
      :ok -> check_voice(rest)
      error -> error
    end
  end

  defp collision(%{kind: :note} = a, %{kind: :note} = b)
       when a.start == b.start and a.ticks == b.ticks do
    if a.event.step == b.event.step, do: {:error, :duplicate}, else: :ok
  end

  defp collision(_a, _b), do: {:error, :overlap}

  defp bar_of(bars, tick),
    do: Enum.find(bars, fn {start, capacity} -> tick >= start and tick < start + capacity end)
end
