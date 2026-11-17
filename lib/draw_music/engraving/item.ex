defmodule DrawMusic.Engraving.Item do
  @moduledoc """
  The things drawn in a system: glyphs, lines, beams, ties, the brace and
  tempo marks, and how far each one reaches (in staff spaces, y down).
  """

  alias DrawMusic.Engraving.{Beam, Brace, Glyph, Line, Smufl, TempoMark, Tie}

  # Half a tie's height; a tempo mark's height above its baseline.
  @tie_extent 1
  @tempo_height 2.0

  @type t :: Glyph.t() | Line.t() | Beam.t() | Tie.t() | Brace.t() | TempoMark.t()

  @doc "The leftmost and rightmost x `item` reaches."
  @spec x_range(t()) :: {number(), number()}
  def x_range(%Glyph{glyph: glyph, x: x}) do
    {x0, _y0, x1, _y1} = Smufl.bbox(glyph)
    {x + x0, x + x1}
  end

  def x_range(%Line{x1: x1, x2: x2}), do: {min(x1, x2), max(x1, x2)}
  def x_range(%Beam{x1: x1, x2: x2}), do: {min(x1, x2), max(x1, x2)}
  def x_range(%Tie{x1: x1, x2: x2}), do: {min(x1, x2), max(x1, x2)}
  def x_range(%Brace{x: x}), do: {x, x}
  def x_range(%TempoMark{} = mark), do: {mark.x, TempoMark.reach(mark)}

  @doc "The y values bounding `item` (its top is the least)."
  @spec y_range(t()) :: [number()]
  def y_range(%Glyph{glyph: glyph, y: y}) do
    {_x0, y0, _x1, y1} = Smufl.bbox(glyph)
    [y - y1, y - y0]
  end

  def y_range(%Line{y1: y1, y2: y2}), do: [y1, y2]
  def y_range(%Beam{} = b), do: [b.y1, b.y2, b.y1 + b.thickness, b.y2 + b.thickness]
  def y_range(%Tie{y: y}), do: [y - @tie_extent, y + @tie_extent]
  def y_range(%Brace{y1: y1, y2: y2}), do: [y1, y2]
  def y_range(%TempoMark{y: y}), do: [y - @tempo_height, y]
end
