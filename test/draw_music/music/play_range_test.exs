defmodule DrawMusic.Music.PlayRangeTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Note, PlayRange, Score}

  # Four bars of 4/4 (3840 ticks each), a C4 quarter on beat 1 of bar 2.
  setup do
    note = %Note{id: Ecto.UUID.generate(), staff: :treble, offset: 0, value: :quarter, step: 28}
    [one, two | rest] = Score.new(4).measures
    %{score: %Score{measures: [one, %{two | notes: [note]} | rest]}, ctx: %Context{}, note: note}
  end

  describe "measures/4" do
    test "measures 2 to 3, both included", %{score: score, ctx: ctx} do
      assert %PlayRange{from: 3840, to: 11_520, first: 2, last: 3, count: 4} =
               PlayRange.measures(score, ctx, 2, 3)
    end

    test "To before From is one measure; past the end, the last", %{score: score, ctx: ctx} do
      assert %PlayRange{first: 3, last: 3} = PlayRange.measures(score, ctx, 3, 1)
      assert %PlayRange{first: 4, last: 4, to: 15_360} = PlayRange.measures(score, ctx, 9, 9)
    end

    test "their ids are what's in them", %{score: score, ctx: ctx, note: note} do
      range = PlayRange.measures(score, ctx, 2, 2)
      assert PlayRange.ids(range, score, ctx) == [note.id]
    end
  end

  describe "of_selection/3" do
    test "nothing selected is the whole piece", %{score: score, ctx: ctx} do
      assert %PlayRange{from: 0, to: 15_360, first: 1, last: 4} =
               PlayRange.of_selection(score, ctx, MapSet.new())
    end

    test "one note plays from it to the end", %{score: score, ctx: ctx, note: note} do
      assert %PlayRange{from: 3840, first: 2, last: 4} =
               PlayRange.of_selection(score, ctx, MapSet.new([note.id]))
    end
  end

  describe "skip/4 and start/2" do
    setup %{score: score, ctx: ctx} do
      %{range: PlayRange.measures(score, ctx, 2, 3), starts: [0, 3840, 7680, 11_520]}
    end

    test "forward stops before the end of the range", %{range: range, starts: starts} do
      assert PlayRange.skip(range, starts, 3840, false) == 7680
      assert PlayRange.skip(range, starts, 7680, false) == nil
    end

    test "back stays inside the range", %{range: range, starts: starts} do
      assert PlayRange.skip(range, starts, 11_520, true) == 7680
      assert PlayRange.skip(range, starts, 5000, true) == 3840
      assert PlayRange.skip(range, starts, 3840, true) == nil
    end

    test "the cursor is kept inside the range", %{range: range} do
      assert PlayRange.start(range, nil) == 3840
      assert PlayRange.start(range, 0) == 3840
      assert PlayRange.start(range, 99_999) == 11_520
    end
  end
end
