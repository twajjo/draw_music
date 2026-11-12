defmodule DrawMusic.Music.TempoEditing do
  @moduledoc """
  Changes to a score's tempo changes (see `DrawMusic.Music.TempoChange`):
  adding or rewriting one, moving it, moving a rit.'s or accel.'s end, and
  deleting. Every change starts inside the score; one tick holds at most
  one change. Results are `{:ok, score}` or `{:error, reason}`, as in
  `DrawMusic.Music.Editing`.
  """

  alias DrawMusic.Music.{Context, Score, TempoChange, Timeline}

  @type result ::
          {:ok, Score.t()} | {:error, :not_found | :past_end | :invalid_tempo | :same_tempo}

  @doc """
  Adds `change`, or rewrites the one with its id. Another change at the
  same tick gives way to it. A rit. or accel. reaches a different tempo
  (`:same_tempo` otherwise), and ends at the latest where the next change
  starts or the score ends; a change put inside one cuts it short there.
  """
  @spec put(Score.t(), Context.t(), TempoChange.t()) :: result()
  def put(%Score{} = score, %Context{} = ctx, %TempoChange{} = change) do
    change = %{change | id: change.id || Ecto.UUID.generate()}
    end_tick = Timeline.end_tick(score, ctx)

    with :ok <- inside(change.tick, end_tick),
         :ok <- changing(change),
         {:ok, change} <- fit_end(change, end_tick) do
      kept = Enum.reject(score.tempos, &(&1.id == change.id or &1.tick == change.tick))
      tempos = Enum.sort_by([change | kept], & &1.tick)
      {:ok, %{score | tempos: within_room(tempos)}}
    end
  end

  @doc "Moves a change to `tick`; a rit. or accel. keeps its length while it fits."
  @spec move(Score.t(), Context.t(), Ecto.UUID.t(), integer()) :: result()
  def move(%Score{} = score, %Context{} = ctx, id, tick) do
    with {:ok, change} <- find(score, id) do
      put(score, ctx, %{
        change
        | tick: tick,
          to_tick: change.to_tick && change.to_tick + tick - change.tick
      })
    end
  end

  @doc "Moves where a rit. or accel. reaches its end tempo."
  @spec resize(Score.t(), Context.t(), Ecto.UUID.t(), integer()) :: result()
  def resize(%Score{} = score, %Context{} = ctx, id, to_tick) do
    case find(score, id) do
      {:ok, %TempoChange{to_tick: nil}} -> {:error, :invalid_tempo}
      {:ok, change} when to_tick > change.tick -> put(score, ctx, %{change | to_tick: to_tick})
      {:ok, _change} -> {:error, :invalid_tempo}
      error -> error
    end
  end

  @doc """
  How far a rit. or accel. starting at `tick` may reach: `{tick,
  :next_change}` where the next change (other than the one with `id`)
  starts, else `{tick, :score_end}` where the score ends.
  """
  @spec reach(Score.t(), Context.t(), non_neg_integer(), Ecto.UUID.t() | nil) ::
          {pos_integer(), :next_change | :score_end}
  def reach(%Score{} = score, %Context{} = ctx, tick, id) do
    end_tick = Timeline.end_tick(score, ctx)

    next =
      score.tempos
      |> Enum.filter(&(&1.id != id and &1.tick > tick and &1.tick < end_tick))
      |> Enum.min_by(& &1.tick, fn -> nil end)

    case next do
      nil -> {end_tick, :score_end}
      change -> {change.tick, :next_change}
    end
  end

  @doc "Removes the changes with these ids (other ids are ignored)."
  @spec remove(Score.t(), [Ecto.UUID.t()]) :: Score.t()
  def remove(%Score{} = score, ids) do
    ids = MapSet.new(ids)
    %{score | tempos: Enum.reject(score.tempos, &(&1.id in ids))}
  end

  @doc "The ids of a score's tempo changes."
  @spec ids(Score.t()) :: [Ecto.UUID.t()]
  def ids(%Score{tempos: tempos}), do: Enum.map(tempos, & &1.id)

  @doc "The change with this id."
  @spec find(Score.t(), Ecto.UUID.t()) :: {:ok, TempoChange.t()} | {:error, :not_found}
  def find(%Score{tempos: tempos}, id) do
    case Enum.find(tempos, &(&1.id == id)) do
      nil -> {:error, :not_found}
      change -> {:ok, change}
    end
  end

  # A rit. or accel. that reaches its own tempo changes nothing.
  defp changing(%TempoChange{to_tick: to_tick, bpm: bpm, to_bpm: bpm}) when to_tick != nil do
    {:error, :same_tempo}
  end

  defp changing(_change), do: :ok

  defp inside(tick, end_tick) when tick >= 0 and tick < end_tick, do: :ok
  defp inside(_tick, _end_tick), do: {:error, :past_end}

  defp fit_end(%TempoChange{to_tick: nil} = change, _end_tick), do: {:ok, change}

  defp fit_end(%TempoChange{} = change, end_tick) do
    case min(change.to_tick, end_tick) do
      to_tick when to_tick > change.tick -> {:ok, %{change | to_tick: to_tick}}
      _none -> {:error, :invalid_tempo}
    end
  end

  # Each rit. or accel. (in tick order) ends at the latest where the next
  # change starts, so two never overlap.
  defp within_room(tempos) do
    next_ticks = tl(Enum.map(tempos, & &1.tick)) ++ [nil]
    Enum.zip_with(tempos, next_ticks, &stop_by/2)
  end

  defp stop_by(%TempoChange{to_tick: to_tick} = change, next)
       when is_integer(to_tick) and is_integer(next) and to_tick > next do
    %{change | to_tick: next}
  end

  defp stop_by(change, _next), do: change
end
