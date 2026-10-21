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

  @doc "Appends an empty measure."
  def append_measure(%Score{measures: measures} = score),
    do: insert_measure(score, length(measures))

  @doc "Deletes measure `index` and its contents. The last measure cannot be deleted."
  def delete_measure(%Score{measures: [_only]}, _ctx, 0), do: {:error, :last_measure}

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
