defmodule DrawMusic.Engraving.LayoutTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Engraving.{Layout, Staff}
  alias DrawMusic.Music.{Context, Editing, Score}

  @ctx %Context{}

  defp items(layout, filter) do
    for system <- layout.systems, item <- system.items, filter.(item), do: item
  end

  defp role(layout, role), do: items(layout, &(Map.get(&1, :role) == role))

  defp place(score \\ Score.new(), ctx \\ @ctx, index \\ 0, spn, attrs) do
    note!(score, ctx, index, spn, Map.merge(%{staff: :treble, offset: 0, value: :quarter}, attrs))
  end

  describe "positions on the staff" do
    test "middle C takes one ledger line on either staff" do
      for staff <- [:treble, :bass] do
        {score, _id} = place("C4", %{staff: staff})
        layout = Layout.layout(score, @ctx)

        assert [%{y1: y}] = role(layout, :ledger)
        assert y == Staff.y(staff, elem(pitch!("C4"), 0))
      end
    end

    test "notes inside the staff need no ledger lines" do
      {score, _id} = place("E4", %{})
      assert role(Layout.layout(score, @ctx), :ledger) == []
    end

    test "the key signature writes its signs on both staves, in order" do
      layout = Layout.layout(Score.new(), %Context{sf: -3})
      key = role(layout, :key)

      assert length(key) == 6
      assert Enum.all?(key, &(&1.glyph == :accidentalFlat))
      # B♭ first: the middle line of the treble staff.
      assert hd(Enum.sort_by(key, &{&1.y > Staff.bottom() / 2, &1.x})).y == Staff.middle(:treble)
    end
  end

  describe "stems and beams" do
    test "stems follow the stem rules, and voices split up and down" do
      {low, _id} = place("C4", %{})
      {high, _id} = place("A5", %{})
      assert [%{dir: :up}] = role(Layout.layout(low, @ctx), :stem)
      assert [%{dir: :down}] = role(Layout.layout(high, @ctx), :stem)

      {two, _id} = place("A5", %{voice: 1})
      {two, _id} = place(two, "C4", %{value: :half, voice: 2})

      assert two |> Layout.layout(@ctx) |> role(:stem) |> Enum.map(& &1.dir) |> Enum.sort() ==
               [:down, :up]
    end

    test "beamed notes get one beam per group and no flags" do
      score =
        Enum.reduce([0, 480, 960, 1440], Score.new(), fn offset, score ->
          elem(place(score, "D5", %{offset: offset, value: :eighth}), 0)
        end)

      layout = Layout.layout(score, @ctx)
      assert length(items(layout, &(&1.type == :beam))) == 2
      assert role(layout, :flag) == []
      assert length(role(layout, :stem)) == 4
    end

    test "a lone eighth gets a flag" do
      {score, _id} = place("D5", %{value: :eighth})
      assert [%{glyph: :flag8thDown}] = role(Layout.layout(score, @ctx), :flag)
    end
  end

  describe "rests and accidentals" do
    test "an empty staff shows a whole-bar rest" do
      {score, _id} = place("C5", %{})
      rests = role(Layout.layout(score, @ctx), :rest)
      assert [%{glyph: :restWhole, id: nil, y: y}] = rests
      assert y == Staff.top(:bass) + 1
    end

    test "a note tied in from the previous bar shows no accidental, nor do later ones in that bar" do
      {score, a} = place(Score.new(2), "C#4", %{offset: 2880})
      {score, b} = place(score, @ctx, 1, "C#4", %{offset: 0})
      {score, _c} = place(score, @ctx, 1, "C#4", %{offset: 960})
      {:ok, score} = Editing.tie(score, @ctx, a, b)

      assert length(role(Layout.layout(score, @ctx), :accidental)) == 1
    end
  end

  test "a score with no measures is drawn as one empty bar" do
    layout = Layout.layout(%Score{measures: []}, @ctx)
    assert [%{measures: [%{index: 0}]}] = layout.systems
  end

  describe "geometry" do
    test "measures map ticks to x and back, and notes sit at their tick" do
      {score, id} = place(Score.new(2), @ctx, 1, "G4", %{offset: 1440, value: :eighth})
      layout = Layout.layout(score, @ctx)
      geom = Enum.at(hd(layout.systems).measures, 1)

      assert Layout.tick_at(geom, Layout.x_of(geom, 5000)) == 5000
      assert [%{x: x}] = items(layout, &(Map.get(&1, :id) == id))
      assert x == Layout.x_of(geom, 3840 + 1440)
    end
  end

  # A 4/4 measure is 35 spaces wide at the default spacing, so at width 80
  # each system holds two measures: 0–1, 2–3, 4–5.
  @page 80

  describe "strip and page layouts" do
    setup do
      {score, a} = place(Score.new(6), @ctx, 1, "G4", %{offset: 1920, value: :half})
      {score, b} = place(score, @ctx, 2, "G4", %{offset: 0, value: :half})
      {:ok, score} = Editing.tie(score, @ctx, a, b)
      %{score: score}
    end

    test "strip is a single system holding every measure", %{score: score} do
      assert [system] = Layout.layout(score, @ctx).systems
      assert Enum.map(system.measures, & &1.index) == Enum.to_list(0..5)
    end

    test "page wraps into systems no wider than the page", %{score: score} do
      layout = Layout.layout(score, @ctx, width: @page)

      assert length(layout.systems) > 1
      assert Enum.all?(layout.systems, &(&1.width <= @page + 1.0e-9))

      assert layout.systems |> Enum.flat_map(& &1.measures) |> Enum.map(& &1.index) ==
               Enum.to_list(0..5)

      ys = Enum.map(layout.systems, & &1.y)
      assert ys == Enum.sort(ys)
    end

    test "only the first system shows the time signature", %{score: score} do
      layout = Layout.layout(score, @ctx, width: @page)
      [first | rest] = layout.systems

      assert Enum.any?(first.items, &(Map.get(&1, :role) == :time))
      refute Enum.any?(rest, fn s -> Enum.any?(s.items, &(Map.get(&1, :role) == :time)) end)

      assert Enum.all?(layout.systems, fn s ->
               Enum.count(s.items, &(Map.get(&1, :role) == :clef)) == 2
             end)
    end

    test "a tie across a system break is drawn as two halves", %{score: score} do
      assert length(items(Layout.layout(score, @ctx), &(&1.type == :tie))) == 1

      layout = Layout.layout(score, @ctx, width: @page)
      system_of = for s <- layout.systems, m <- s.measures, into: %{}, do: {m.index, s.index}
      assert system_of[1] != system_of[2]

      ties = for s <- layout.systems, item <- s.items, item.type == :tie, do: s.index
      assert Enum.sort(ties) == [system_of[1], system_of[2]]
    end
  end
end
