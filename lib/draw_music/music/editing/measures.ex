defmodule DrawMusic.Music.Editing.Measures do
  @moduledoc """
  Adding and deleting bars, for `DrawMusic.Music.Editing` (whose moduledoc
  has the score's rules). Tempo changes after the bar move with the music;
  ties a new bar separates are dropped.
  """

  alias DrawMusic.Music.{Context, Editing, Fillers, Measure, Score, TempoChange, Ties}

  @doc "Appends a measure of filler rests."
  @spec append_measure(Score.t(), Context.t()) :: Editing.result()
  def append_measure(%Score{measures: measures} = score, %Context{} = ctx) do
    insert_measure(score, ctx, length(measures))
  end

  @doc """
  Deletes measure `index` and its contents, its tempo changes included;
  later ones move back with the music. The last measure cannot be deleted,
  nor the pickup bar (remove the pickup in the settings instead).
  """
  @spec delete_measure(Score.t(), Context.t(), non_neg_integer()) :: Editing.result()
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

  @doc """
  Inserts a measure of filler rests before `index` (`index == length`
  appends), dropping ties the new bar separates.
  """
  @spec insert_measure(Score.t(), Context.t(), non_neg_integer()) :: Editing.result()
  def insert_measure(%Score{} = score, %Context{} = ctx, index) do
    with {:ok, score} <- empty_measure_at(score, index) do
      at = Context.span(ctx, index)
      tempos = shift_tempos(score.tempos, at, Context.capacity(ctx, index))
      {:ok, %{score | tempos: tempos} |> Ties.prune(ctx) |> Fillers.fill(ctx)}
    end
  end

  defp empty_measure_at(%Score{measures: measures} = score, index)
       when is_integer(index) and index >= 0 and index <= length(measures) do
    {:ok, %{score | measures: List.insert_at(measures, index, Measure.new())}}
  end

  defp empty_measure_at(_score, _index), do: {:error, :no_such_measure}

  defp keep_ramp_forward(%TempoChange{to_tick: to_tick, tick: tick} = change)
       when is_integer(to_tick) and to_tick <= tick do
    %{change | to_tick: nil, bpm: change.to_bpm, to_bpm: nil}
  end

  defp keep_ramp_forward(change), do: change

  defp shift_field(change, field, at, delta) do
    case Map.fetch!(change, field) do
      tick when is_integer(tick) and tick >= at -> Map.put(change, field, tick + delta)
      _before -> change
    end
  end

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
end
