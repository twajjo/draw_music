defmodule DrawMusic.Music.Editing.Place do
  @moduledoc """
  Placing notes, chords and rests where a `DrawMusic.Music.Placement` says,
  for `DrawMusic.Music.Editing` (whose moduledoc has the score's rules).
  Without a voice, an event goes in the lowest voice it fits; overwriting
  clears the time first, so the first voice takes it.
  """

  alias DrawMusic.Music.{
    Context,
    Duration,
    Editing,
    Entry,
    Note,
    Placement,
    Rest,
    Score,
    Timeline
  }

  alias DrawMusic.Music.Editing.{Rebuild, Time}

  @doc """
  Places a chord: one note per `{step, alter}` in `pitches`, all at the
  placement's position and length, in one voice (the placement's own step
  and alter are not used).
  """
  @spec place_chord(Score.t(), Context.t(), non_neg_integer(), Placement.t(), [{integer(), -2..2}]) ::
          {:ok, Score.t(), [Editing.id()]} | {:error, Editing.reason()}
  def place_chord(%Score{} = score, %Context{} = ctx, index, %Placement{} = placement, pitches) do
    build = fn voice ->
      Enum.map(pitches, fn {step, alter} -> new_note(placement, voice, step, alter) end)
    end

    with {:ok, score, notes} <- place(score, ctx, index, placement, build) do
      {:ok, score, Enum.map(notes, & &1.id)}
    end
  end

  @doc """
  Places a note in measure `index` as `placement` describes (its `step` and
  `alter` give the pitch).
  """
  @spec place_note(Score.t(), Context.t(), non_neg_integer(), Placement.t()) ::
          {:ok, Score.t(), Editing.id()} | {:error, Editing.reason()}
  def place_note(%Score{} = score, %Context{} = ctx, index, %Placement{} = placement) do
    build = fn voice ->
      [new_note(placement, voice, placement.step, placement.alter)]
    end

    with {:ok, score, [note]} <- place(score, ctx, index, placement, build) do
      {:ok, score, note.id}
    end
  end

  @doc "Places a rest in measure `index` as `placement` describes (its pitch is not used)."
  @spec place_rest(Score.t(), Context.t(), non_neg_integer(), Placement.t()) ::
          {:ok, Score.t(), Editing.id()} | {:error, Editing.reason()}
  def place_rest(%Score{} = score, %Context{} = ctx, index, %Placement{} = placement) do
    build = fn voice ->
      [Rest.from(placement, id: Ecto.UUID.generate(), voice: voice)]
    end

    with {:ok, score, [rest]} <- place(score, ctx, index, placement, build) do
      {:ok, score, rest.id}
    end
  end

  # The new entries' time on their staff, in every voice, becomes theirs
  # (see `DrawMusic.Music.Editing.Time.clear_span/4`).
  defp clear_span(entries, [first | _] = new_entries) do
    to = Enum.max(Enum.map(new_entries, &Entry.end_tick/1))
    Time.clear_span(entries, [first.event.staff], first.start, to)
  end

  # The tick where `event` starts in bar `index`. It must fit in the bar, or,
  # placed to cross bar lines (`cross?`), just start inside it.
  defp locate(score, ctx, index, event, cross?) when is_integer(index) and index >= 0 do
    case Enum.at(Timeline.bars(score, ctx), index) do
      nil ->
        {:error, :no_such_measure}

      {start, _capacity} = bar ->
        at = start + event.offset

        with :ok <- Rebuild.ensure(Timeline.fits?(bar, at, room(event, cross?)), :measure_full),
             do: {:ok, at}
    end
  end

  defp locate(_score, _ctx, _index, _event, _cross?), do: {:error, :no_such_measure}

  defp new_note(%Placement{} = placement, voice, step, alter) do
    Note.from(placement, id: Ecto.UUID.generate(), voice: voice, step: step, alter: alter)
  end

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

  defp place_events(score, ctx, index, [first | _] = events, cross?) do
    with {:ok, start} <- locate(score, ctx, index, first, cross?) do
      Rebuild.add(score, ctx, Enum.map(events, &%{Timeline.entry(&1, 0) | start: start}))
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

  # How much of `event` must fit in its bar: one tick (its start) when it may
  # cross the bar line, else all of it.
  defp room(_event, true = _cross?), do: 1
  defp room(event, _cross?), do: Duration.ticks(event.value, event.dots)

  defp voices_to_try(nil), do: Note.voices()
  defp voices_to_try(voice), do: [voice]
end
