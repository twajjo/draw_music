defmodule DrawMusicWeb.ScoreSvgTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Engraving.{Glyph, Layout}
  alias DrawMusic.Music.{Context, Score}
  alias DrawMusicWeb.{ScoreComponents, ScoreSvg}

  @ctx %Context{}

  defp engrave(score, layout),
    do: Layout.layout(score, @ctx, width: ScoreComponents.layout_width(layout))

  defp glyph_ids(pieces) do
    for piece <- pieces, {_i, _y, items} <- piece.groups, %Glyph{id: id} <- items, id, do: id
  end

  describe "Page layout" do
    test "a piece per system, whose bands tile the page from top to bottom" do
      engraved = engrave(Score.new(40), :page)
      pieces = ScoreSvg.pieces(engraved, :page)

      assert length(pieces) == length(engraved.systems) and length(pieces) > 1
      assert hd(pieces).y0 == 0.0
      assert List.last(pieces).y1 == engraved.height

      for {above, below} <- Enum.zip(pieces, tl(pieces)), do: assert(above.y1 == below.y0)
    end
  end

  describe "Strip layout" do
    test "runs of bars that tile the score's width, cut at barlines" do
      engraved = engrave(Score.new(40), :strip)
      [system] = engraved.systems
      pieces = ScoreSvg.pieces(engraved, :strip)

      assert length(pieces) == 3
      assert hd(pieces).x0 == -ScoreSvg.padding()
      assert List.last(pieces).x1 == engraved.width + ScoreSvg.padding()

      for {left, right} <- Enum.zip(pieces, tl(pieces)) do
        assert left.x1 == right.x0
        assert Enum.any?(system.measures, &(&1.x == right.x0))
      end
    end

    test "every note and rest is drawn in exactly one run" do
      {score, _id} =
        note!(Score.new(40), @ctx, 20, "C4", %{staff: :treble, offset: 0, value: :quarter})

      engraved = engrave(score, :strip)
      [system] = engraved.systems
      ids = for %Glyph{id: id} <- system.items, id, do: id

      assert Enum.sort(glyph_ids(ScoreSvg.pieces(engraved, :strip))) == Enum.sort(ids)
    end
  end

  test "a piece knows only its own selected notes" do
    {score, id} =
      note!(Score.new(40), @ctx, 0, "C4", %{staff: :treble, offset: 0, value: :quarter})

    engraved = engrave(score, :page)

    [first | rest] =
      engraved
      |> ScoreSvg.pieces(:page)
      |> ScoreSvg.select(MapSet.new([id]))

    assert first.selected == MapSet.new([id])
    assert Enum.all?(rest, &(&1.selected == MapSet.new()))
    assert IO.iodata_to_binary(ScoreSvg.piece(first, 10)) =~ ~s(id="note-#{id}" class="selected")
  end
end
