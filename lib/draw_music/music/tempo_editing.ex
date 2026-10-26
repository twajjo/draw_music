defmodule DrawMusic.Music.TempoEditing do
  @moduledoc """
  Changes to a score's tempo changes (see `DrawMusic.Music.TempoChange`):
  adding or rewriting one, moving it, moving a rit.'s or accel.'s end, and
  deleting. Every change starts inside the score; one tick holds at most
  one change. Results are `{:ok, score}` or `{:error, reason}`, as in
  `DrawMusic.Music.Editing`.
  """

  alias DrawMusic.Music.{Context, Score, TempoChange, Timeline}

  @type result :: {:ok, Score.t()} | {:error, :not_found | :past_end | :invalid_tempo}

  @doc """
  Adds `change`, or rewrites the one with its id. Another change at the
  same tick gives way to it. A rit. or accel. ends at the latest at the
  score's end.
  """
  @spec put(Score.t(), Context.t(), TempoChange.t()) :: result()
  def put(%Score{} = score, %Context{} = ctx, %TempoChange{} = change) do
    change = %{change | id: change.id || Ecto.UUID.generate()}
    end_tick = Timeline.end_tick(score, ctx)

    with :ok <- inside(change.tick, end_tick),
         {:ok, change} <- fit_end(change, end_tick) do
      kept = Enum.reject(score.tempos, &(&1.id == change.id or &1.tick == change.tick))
      {:ok, %{score | tempos: Enum.sort_by([change | kept], & &1.tick)}}
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

  defp inside(tick, end_tick) when tick >= 0 and tick < end_tick, do: :ok
  defp inside(_tick, _end_tick), do: {:error, :past_end}

  defp fit_end(%TempoChange{to_tick: nil} = change, _end_tick), do: {:ok, change}

  defp fit_end(%TempoChange{} = change, end_tick) do
    case min(change.to_tick, end_tick) do
      to_tick when to_tick > change.tick -> {:ok, %{change | to_tick: to_tick}}
      _none -> {:error, :invalid_tempo}
    end
  end
end
