defmodule DrawMusic.Music.Editing.Rebuild do
  @moduledoc """
  What every edit in `DrawMusic.Music.Editing` ends with: its entries (the
  score on one time axis, see `DrawMusic.Music.Timeline`) checked against
  the score's rules, put back into bars, ties that no longer hold dropped,
  and the filler rests written afresh. The rules are in `Editing`'s
  moduledoc.
  """

  alias DrawMusic.Music.{Context, Editing, Entry, Fillers, Pitch, Score, Spans, Ties, Timeline}

  @typedoc "Changes one entry, or refuses with a reason."
  @type mapper :: (Entry.t() -> {:ok, Entry.t()} | {:error, Editing.reason()})

  @doc """
  Adds `new_entries` to the score: new notes take the place of the rests
  they cover in their voice.
  """
  @spec add(Score.t(), Context.t(), [Entry.t()]) :: Editing.result()
  def add(%Score{} = score, %Context{} = ctx, new_entries) do
    rebuild(
      score,
      ctx,
      clear_rests_under(Timeline.flatten(score, ctx), new_entries) ++ new_entries
    )
  end

  @doc "`entries` without the rests that `new_entries`' notes cover in their voice."
  @spec clear_rests_under([Entry.t()], [Entry.t()]) :: [Entry.t()]
  def clear_rests_under(entries, new_entries) do
    notes = Enum.filter(new_entries, &(&1.kind == :note))

    Enum.reject(entries, fn entry ->
      entry.kind == :rest and Enum.any?(notes, &Spans.overlapping_in_voice?(&1, entry))
    end)
  end

  @doc "A yes/no check as an edit step: `:ok`, or `{:error, reason}`."
  @spec ensure(boolean(), Editing.reason()) :: :ok | {:error, Editing.reason()}
  def ensure(true, _reason), do: :ok
  def ensure(false, reason), do: {:error, reason}

  @doc """
  The score's entries with `fun` applied to those among `ids`; `fun`
  returns `{:ok, entry}` or an error, which stops it.
  """
  @spec map_entries(Score.t(), Context.t(), Enumerable.t(), mapper()) ::
          {:ok, [Entry.t()]} | {:error, Editing.reason()}
  def map_entries(%Score{} = score, %Context{} = ctx, ids, fun) do
    ids = MapSet.new(ids)

    score
    |> Timeline.flatten(ctx)
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      entry
      |> apply_if_selected(ids, fun)
      |> collect(acc)
    end)
  end

  @doc "`map_entries/4`, then the score rebuilt from them."
  @spec map_selected(Score.t(), Context.t(), Enumerable.t(), mapper()) :: Editing.result()
  def map_selected(%Score{} = score, %Context{} = ctx, ids, fun) do
    with {:ok, entries} <- map_entries(score, ctx, ids, fun), do: rebuild(score, ctx, entries)
  end

  @doc """
  The score made from `entries`, if they keep its rules: filler is dropped
  and written afresh once the events are in their bars.
  """
  @spec rebuild(Score.t(), Context.t(), [Entry.t()]) :: Editing.result()
  def rebuild(%Score{} = score, %Context{} = ctx, entries) do
    entries = Enum.reject(entries, &Fillers.filler?/1)

    with :ok <- check_layout(entries),
         {:ok, rebarred} <- Timeline.rebar(score, ctx, entries) do
      {:ok, rebarred |> Ties.prune(ctx) |> Fillers.refill(ctx, Fillers.ids(score))}
    end
  end

  defp apply_if_selected(entry, ids, fun) do
    if entry.event.id in ids, do: fun.(entry), else: {:ok, entry}
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

  defp check_range(entries) do
    case Enum.reject(entries, &in_range?/1) do
      [] -> :ok
      _out_of_range -> {:error, :out_of_range}
    end
  end

  # Entries of one voice, sorted by start; compare each with the ones that
  # begin before it ends.
  defp check_voice([]), do: :ok

  defp check_voice([entry | rest]) do
    rest
    |> Enum.take_while(&(&1.start < Entry.end_tick(entry)))
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

  defp collect({:ok, entry}, acc), do: {:cont, {:ok, [entry | acc]}}
  defp collect(error, _acc), do: {:halt, error}

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

  defp continue_if_ok(:ok), do: {:cont, :ok}
  defp continue_if_ok(error), do: {:halt, error}

  defp in_range?(%{kind: :note, event: note}), do: Pitch.playable?(note.step, note.alter)
  defp in_range?(_entry), do: true
end
