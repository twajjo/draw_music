defmodule DrawMusic.Music.Playback do
  @moduledoc """
  What a score sounds like: one sound per note or tied chain of notes, with
  its start and length in ticks and seconds.
  """

  alias DrawMusic.Music.{Context, Duration, Note, Pitch, PlaybackEvent, Score, Sound, Timeline}

  @seconds_per_minute 60

  @doc """
  The score's sounds, ordered by start: a tied chain sounds once, for its
  total length.
  """
  @spec sounds(Score.t(), Context.t()) :: [Sound.t()]
  def sounds(%Score{} = score, %Context{} = ctx) do
    notes = for %{kind: :note} = entry <- Timeline.flatten(score, ctx), do: entry
    by_id = Map.new(notes, &{&1.event.id, &1})

    tie_targets =
      for n <- notes, Map.has_key?(by_id, n.event.tie_to), into: MapSet.new(), do: n.event.tie_to

    notes
    |> Enum.reject(&(&1.event.id in tie_targets))
    |> Enum.map(&chain(&1, by_id))
    |> Enum.sort_by(&{&1.start, &1.midi})
  end

  defp chain(head, by_id) do
    {ids, ticks} = follow(head, by_id, [], 0)

    %Sound{
      ids: ids,
      staff: head.event.staff,
      midi: Note.midi(head.event),
      start: head.start,
      ticks: ticks
    }
  end

  defp follow(entry, by_id, ids, ticks) do
    ids = [entry.event.id | ids]
    ticks = ticks + entry.ticks

    case Map.get(by_id, entry.event.tie_to) do
      # The id check guards against a malformed (cyclic) tie chain.
      %{event: %{id: next_id}} = next ->
        if next_id in ids, do: {Enum.reverse(ids), ticks}, else: follow(next, by_id, ids, ticks)

      nil ->
        {Enum.reverse(ids), ticks}
    end
  end

  @doc """
  The chord a note belongs to, to sound at once: every note on its staff
  that starts with it, each for its own written length, timed from 0.
  Nothing for a rest or an unknown id.
  """
  @spec chord_at(Score.t(), Context.t(), Ecto.UUID.t()) :: [PlaybackEvent.t()]
  def chord_at(%Score{} = score, %Context{} = ctx, id) do
    notes = for %{kind: :note} = entry <- Timeline.flatten(score, ctx), do: entry

    case Enum.find(notes, &(&1.event.id == id)) do
      nil ->
        []

      clicked ->
        for entry <- notes,
            entry.start == clicked.start,
            entry.event.staff == clicked.event.staff do
          event(
            [entry.event.id],
            Note.midi(entry.event),
            entry.start,
            entry.start,
            entry.ticks,
            ctx
          )
        end
    end
  end

  @doc """
  Sounds to play, timed in seconds at the context's tempo. Options:
  `:from` and `:to` (ticks) limit playback to sounds starting in that span;
  times are relative to `:from`.
  """
  @spec events(Score.t(), Context.t(), from: non_neg_integer(), to: non_neg_integer()) ::
          [PlaybackEvent.t()]
  def events(%Score{} = score, %Context{} = ctx, opts \\ []) do
    from = Keyword.get(opts, :from, 0)
    to = Keyword.get(opts, :to)

    for sound <- sounds(score, ctx), sound.start >= from, is_nil(to) or sound.start < to do
      event(sound.ids, sound.midi, sound.start, from, sound.ticks, ctx)
    end
  end

  defp event(ids, midi, tick, from, ticks, ctx) do
    seconds_per_tick = @seconds_per_minute / (ctx.tempo_bpm * Duration.ppq())

    %PlaybackEvent{
      ids: ids,
      midi: midi,
      frequency: Pitch.frequency(midi),
      tick: tick,
      start: (tick - from) * seconds_per_tick,
      duration: ticks * seconds_per_tick
    }
  end
end
