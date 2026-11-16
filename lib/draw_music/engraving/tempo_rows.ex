defmodule DrawMusic.Engraving.TempoRows do
  @moduledoc """
  Where a system's tempo marks go up and down.

  Each mark sits just above what rises over the treble staff where it is
  (from its start to where its words or line end), not above the highest
  thing in the whole system: a long system, like the Strip layout's one for
  the whole piece, may have very high notes far away, and a mark at the
  start would otherwise float far above its own music.

  Marks that would overlap go up a row, left to right, each taking the
  lowest row it fits in, and always above the marks it climbs over.
  """

  alias DrawMusic.Engraving.{Item, TempoMark}

  # The bottom row's baseline sits this far above whatever is highest
  # (clear of the editor's bar buttons, centred 2.2 above the top line:
  # `DrawMusicWeb.EditorComponents.measure_controls/1`); rows are this far
  # apart; marks on one row keep this gap; crowded marks go up to this row
  # (from 0).
  @clearance 3.5
  @row 2.4
  @gap 0.8
  @max_row 3

  @doc "`marks` given their `y`, over a system's other `items`."
  @spec place([TempoMark.t()], [Item.t()]) :: [TempoMark.t()]
  def place(marks, items) do
    # Only what rises above the top line can push a mark up.
    tops =
      for item <- items,
          top = Enum.min(Item.y_range(item)),
          top < 0,
          do: {Item.x_range(item), top}

    {placed, _rows} =
      marks
      |> Enum.sort_by(& &1.x)
      |> Enum.map_reduce(%{}, fn mark, rows ->
        row = Enum.find(0..@max_row, @max_row, &free?(rows, &1, mark))
        y = y_in(row, baseline(mark, tops), rows)
        {%{mark | y: y}, Map.put(rows, row, {TempoMark.reach(mark) + @gap, y})}
      end)

    placed
  end

  # The bottom row's baseline for `mark`: above everything over the treble
  # staff from its start to its end.
  defp baseline(mark, tops) do
    from = mark.x - @gap
    to = TempoMark.reach(mark) + @gap

    top =
      for {{x0, x1}, top} <- tops, x1 >= from, x0 <= to, reduce: 0.0 do
        highest -> min(highest, top)
      end

    top - @clearance
  end

  defp free?(rows, row, mark) do
    case Map.get(rows, row) do
      nil -> true
      {reaches, _y} -> mark.x >= reaches
    end
  end

  # A mark on `row` sits its rows above its own baseline, and above every
  # mark on the rows below, which it overlaps (or it would be lower).
  defp y_in(row, baseline, rows) do
    for below <- 0..(row - 1)//1, reduce: baseline - row * @row do
      y ->
        {_reaches, below_y} = Map.fetch!(rows, below)
        min(y, below_y - (row - below) * @row)
    end
  end
end
