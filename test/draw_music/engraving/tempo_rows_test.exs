defmodule DrawMusic.Engraving.TempoRowsTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Engraving.{Line, TempoMark, TempoRows}

  test "a mark sits above its own music, not a high note far away" do
    near = stem(10.0, -2.0)
    far = stem(500.0, -14.0)

    [mark] = TempoRows.place([mark(8.0)], [near, far])

    assert mark.y == -2.0 - 3.5
  end

  test "with nothing above the staff, a mark clears the bar buttons" do
    [mark] = TempoRows.place([mark(8.0)], [stem(10.0, 2.0)])
    assert mark.y == -3.5
  end

  test "an overlapping mark goes up a row, above the one it climbs over" do
    # Only the first mark's music rises; the second's alone would leave it
    # lower than the first.
    high = stem(8.5, -6.0)

    [first, second] = TempoRows.place([mark(8.0), mark(12.0)], [high])

    assert first.y == -6.0 - 3.5
    assert_in_delta second.y, first.y - 2.4, 1.0e-9
  end

  test "marks apart share the bottom row" do
    [a, b] = TempoRows.place([mark(0.0), mark(100.0)], [])
    assert a.y == b.y
  end

  defp mark(x) do
    %TempoMark{id: nil, x: x, y: 0.0, bpm: 90, width: 5.0}
  end

  defp stem(x, top) do
    %Line{role: :stem, x1: x, y1: 4.0, x2: x, y2: top, thickness: 0.1}
  end
end
