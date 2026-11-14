defmodule DrawMusic.Music.PlayRange do
  @moduledoc """
  The part of a score Play plays: from tick `from` up to (not including)
  tick `to`, covering measures `first` to `last` (numbered from 1, both
  included) of the score's `count`. Loop repeats it, and the transport's
  skips stay inside it.

  It comes from the selection (`of_selection/3`, the span
  `DrawMusic.Music.Playback.span/3` gives) or from chosen measures
  (`measures/4`). Where in it Play starts is a tick from `from` to `to`
  (`start/2`); at `to`, the range has been played to its end.
  """

  alias DrawMusic.Music.{Context, Editing, Playback, Score, Timeline}

  @enforce_keys [:from, :to, :first, :last, :count]
  defstruct [:from, :to, :first, :last, :count]

  @type t :: %__MODULE__{
          from: non_neg_integer(),
          to: non_neg_integer(),
          first: pos_integer(),
          last: pos_integer(),
          count: pos_integer()
        }

  @doc """
  The ids of the notes and rests in the range's measures, which selecting
  measures selects.
  """
  @spec ids(t(), Score.t(), Context.t()) :: [Ecto.UUID.t()]
  def ids(%__MODULE__{from: from, to: to}, %Score{} = score, %Context{} = ctx) do
    Editing.select_range(score, ctx, from, to)
  end

  @doc """
  Measures `first` to `last`, kept inside the score: `last` is at least
  `first`, as the measure lists offer.
  """
  @spec measures(Score.t(), Context.t(), pos_integer(), pos_integer()) :: t()
  def measures(%Score{} = score, %Context{} = ctx, first, last) do
    bars = Timeline.bars(score, ctx)
    count = length(bars)
    first = first |> max(1) |> min(count)
    last = last |> max(first) |> min(count)
    {from, _capacity} = Enum.at(bars, first - 1)
    {start, capacity} = Enum.at(bars, last - 1)
    %__MODULE__{from: from, to: start + capacity, first: first, last: last, count: count}
  end

  @doc "The span the selection plays, and the measures it reaches into."
  @spec of_selection(Score.t(), Context.t(), MapSet.t(Ecto.UUID.t())) :: t()
  def of_selection(%Score{} = score, %Context{} = ctx, selection) do
    bars = Timeline.bars(score, ctx)
    {from, to} = Playback.span(score, ctx, selection)

    %__MODULE__{
      from: from,
      to: to,
      first: measure_at(bars, from),
      last: measure_at(bars, max(from, to - 1)),
      count: length(bars)
    }
  end

  @doc """
  Where a skip from `start` lands among `points` (ticks, in order), inside
  the range: forward, the next point before its end; back, the last point
  before `start`, or the range's own start. Nil when it goes nowhere.
  """
  @spec skip(t(), [non_neg_integer()], non_neg_integer(), boolean()) :: non_neg_integer() | nil
  def skip(%__MODULE__{to: to}, points, start, false = _back?) do
    Enum.find(points, &(&1 > start and &1 < to))
  end

  def skip(%__MODULE__{from: from}, points, start, true = _back?) do
    points
    |> Enum.filter(&(&1 >= from and &1 < start))
    |> List.last()
    |> Kernel.||(if start > from, do: from)
  end

  @doc """
  Where Play starts: `cursor` (a tick the transport moved it to) kept
  inside the range, or the range's start.
  """
  @spec start(t(), non_neg_integer() | nil) :: non_neg_integer()
  def start(%__MODULE__{from: from}, nil), do: from
  def start(%__MODULE__{from: from, to: to}, cursor), do: cursor |> max(from) |> min(to)

  # The number (from 1) of the measure holding `tick`.
  defp measure_at(bars, tick) do
    index = Enum.find_index(bars, fn {start, capacity} -> tick < start + capacity end)
    (index || length(bars) - 1) + 1
  end
end
