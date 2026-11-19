defmodule DrawMusic.Music.GapsTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Duration, Gaps, Measure, Note}

  @q Duration.ticks(:quarter)
  @e Duration.ticks(:eighth)

  describe "simple meters show the beats" do
    test "4/4: a half rest only on beat 1 or 3; beats 2–3 are two quarter rests" do
      assert rests({4, 4}, [{0, :quarter, 0}]) == [{960, :quarter, 0}, {1920, :half, 0}]

      assert rests({4, 4}, [{0, :quarter, 0}, {3 * @q, :quarter, 0}]) ==
               [{960, :quarter, 0}, {1920, :quarter, 0}]
    end

    test "3/4: after beat 1, two quarter rests; an empty bar is one rest" do
      assert rests({3, 4}, [{0, :quarter, 0}]) == [{960, :quarter, 0}, {1920, :quarter, 0}]
      assert rests({3, 4}, []) == [{0, :half, 1}]
    end
  end

  describe "compound meters rest a dotted beat at a time" do
    test "6/8: a silent beat is a dotted quarter rest" do
      assert rests({6, 8}, [{0, :quarter, 1}]) == [{3 * @e, :quarter, 1}]
      assert rests({6, 8}, [{3 * @e, :quarter, 1}]) == [{0, :quarter, 1}]
    end

    test "6/8: inside a beat, rests don't cross into the next one" do
      assert rests({6, 8}, [{0, :eighth, 0}]) ==
               [{@e, :eighth, 0}, {2 * @e, :eighth, 0}, {3 * @e, :quarter, 1}]
    end

    test "12/8: two beats on beat 1 or 3 are a dotted half rest; beats 2–3 are two dotted quarters" do
      assert rests({12, 8}, [{9 * @e, :quarter, 1}]) == [{0, :half, 1}, {6 * @e, :quarter, 1}]

      assert rests({12, 8}, [{0, :quarter, 1}]) ==
               [{3 * @e, :quarter, 1}, {6 * @e, :half, 1}]
    end

    test "9/8: beats 2–3 are two dotted quarter rests" do
      assert rests({9, 8}, [{0, :quarter, 1}]) == [{3 * @e, :quarter, 1}, {6 * @e, :quarter, 1}]
    end
  end

  # The treble staff's filler rests as {offset, value, dots}, in order,
  # around the given notes.
  defp rests({num, den}, notes) do
    ctx = %Context{time_num: num, time_den: den}

    measure = %Measure{
      notes:
        for {offset, value, dots} <- notes do
          %Note{staff: :treble, voice: 1, offset: offset, value: value, dots: dots, step: 30}
        end,
      rests: []
    }

    for rest <- Gaps.rests(measure, Context.measure_ticks(ctx), ctx), rest.staff == :treble do
      {rest.offset, rest.value, rest.dots}
    end
    |> Enum.sort()
  end
end
