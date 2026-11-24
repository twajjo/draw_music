defmodule DrawMusic.Music.SilentBarsTest do
  @moduledoc """
  A bar with no notes whose filler rests take several values (5/4, 9/8) is
  drawn as one whole-bar rest, and selected as one item.
  """
  use ExUnit.Case, async: true

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Music.{Context, Duration, Fillers, Score, Session}

  @five_four %Context{time_num: 5, time_den: 4}
  @nine_eight %Context{time_num: 9, time_den: 8}

  describe "drawing" do
    test "an empty bar in 5/4 or 9/8 is one whole-bar rest per staff" do
      for ctx <- [@five_four, @nine_eight] do
        session = Session.new(Score.new(), ctx)
        [measure] = session.score.measures
        assert length(measure.rests) == 4, "two filler rests on each staff"

        layout = Layout.layout(session.score, ctx)
        [geometry] = layout.systems |> hd() |> Map.get(:measures)
        assert geometry.bar_rests == [:treble, :bass]

        assert [%{glyph: :restWhole} = a, %{glyph: :restWhole} = b] = rests(layout)
        assert Enum.sort([a.id, b.id]) == Enum.sort(first_ids(measure))
      end
    end

    test "rests the user placed are drawn as written" do
      session = Session.new(Score.new(), @five_four)
      [measure] = session.score.measures
      claimed = %{measure | rests: Enum.map(measure.rests, &Fillers.claim/1)}
      score = %{session.score | measures: [claimed]}

      refute Fillers.silent_bar?(claimed, :treble)
      assert length(rests(Layout.layout(score, @five_four))) == 4
    end
  end

  describe "selecting" do
    test "a click on the bar rest selects the whole bar's rests, and the cursor goes after it" do
      session = Session.new(Score.new(), @five_four)
      [measure] = session.score.measures
      [first, second] = staff_ids(measure, :treble)

      selected = Session.select(session, [first], false)

      assert Enum.sort(Session.selection_ids(selected)) == Enum.sort([first, second])
      assert selected.cursor == 5 * Duration.ppq()
    end

    test "toggling the bar rest takes all its rests out again" do
      session = Session.new(Score.new(), @nine_eight)
      [measure] = session.score.measures
      [first, _second] = staff_ids(measure, :bass)

      toggled = session |> Session.toggle(first) |> Session.toggle(first)

      assert Session.selection_ids(toggled) == []
    end
  end

  defp first_ids(measure) do
    for staff <- [:treble, :bass], do: hd(staff_ids(measure, staff))
  end

  defp rests(layout) do
    for system <- layout.systems, %{role: :rest} = item <- system.items, do: item
  end

  defp staff_ids(measure, staff) do
    for rest <- Enum.sort_by(measure.rests, & &1.offset), rest.staff == staff, do: rest.id
  end
end
