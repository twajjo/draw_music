defmodule DrawMusic.Engraving.MeasureGeometry do
  @moduledoc """
  Where a measure sits in its system, and how its ticks map to x. Sent to
  the editor's browser hook as JSON.

  Notes and rests are drawn at their `columns`. Each column has an
  insertion `gap` to its left, and after it at least `min_space`, or more
  for a longer note: so a measure is as wide as its contents need while
  still holding one bar of beats. Between a column and the next one's gap
  ticks map to x linearly; the gap itself is the next column's offset.
  `content_x` is beat 1 and `content_end` the end of the last column's
  space. A measure with no columns maps linearly with `scale` (staff spaces
  per tick).
  """

  alias DrawMusic.Engraving.Column

  @derive Jason.Encoder
  @enforce_keys [
    :index,
    :x,
    :width,
    :start_tick,
    :capacity,
    :content_x,
    :content_end,
    :scale,
    :gap,
    :columns
  ]
  defstruct [
    :index,
    :x,
    :width,
    :start_tick,
    :capacity,
    :content_x,
    :content_end,
    :scale,
    :gap,
    :columns
  ]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          x: float(),
          width: float(),
          start_tick: non_neg_integer(),
          capacity: pos_integer(),
          content_x: float(),
          content_end: float(),
          scale: float(),
          gap: float(),
          columns: [Column.t()]
        }

  @doc "x of `offset` ticks into the measure."
  @spec x_at(t(), number()) :: float()
  def x_at(%__MODULE__{columns: []} = geom, offset), do: geom.content_x + offset * geom.scale

  def x_at(%__MODULE__{} = geom, offset) do
    {from, to} = segment_at(geom, offset)
    from.x + (offset - from.offset) / (to.offset - from.offset) * (to.x - from.x)
  end

  @doc "Ticks into the measure at `x` (in a gap: the next column's offset)."
  @spec offset_at(t(), number()) :: float()
  def offset_at(%__MODULE__{columns: []} = geom, x), do: (x - geom.content_x) / geom.scale

  def offset_at(%__MODULE__{} = geom, x) do
    segments = segments(geom)

    case Enum.find(segments, fn {_from, to} -> x < to.x end) || List.last(segments) do
      {from, _to} when x <= from.x -> from.offset
      {from, to} -> from.offset + (x - from.x) / (to.x - from.x) * (to.offset - from.offset)
    end
  end

  # The linear stretches: each column to the start of the next one's gap,
  # and the last one to the end of the content.
  defp segments(%__MODULE__{columns: columns} = geom) do
    ends =
      Enum.map(tl(columns), &%{offset: &1.offset, x: &1.x - geom.gap}) ++
        [%{offset: geom.capacity, x: geom.content_end}]

    columns
    |> Enum.map(&%{offset: &1.offset, x: &1.x})
    |> Enum.zip(ends)
  end

  defp segment_at(geom, offset) do
    segments = segments(geom)
    Enum.find(segments, fn {_from, to} -> offset < to.offset end) || List.last(segments)
  end
end
