defmodule DrawMusic.Music.ZoneTicksTest do
  @moduledoc """
  Overlay's placement zones (plans/overlay-zones.md): where an armed item
  may start, so that the zones show the beat.
  """
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Duration}

  @four_four %Context{}
  @two_two %Context{time_num: 2, time_den: 2}
  @six_eight %Context{time_num: 6, time_den: 8}
  @twelve_eight %Context{time_num: 12, time_den: 8}

  test "shorter than a beat and dividing it: zones of the item's own length" do
    assert zone(@four_four, :eighth) == ticks(:eighth)
    assert zone(@twelve_eight, :eighth) == ticks(:eighth)
    assert zone(@two_two, :quarter) == ticks(:quarter)
    assert zone(@six_eight, :sixteenth) == ticks(:sixteenth)
  end

  test "a value that doesn't divide the beat gets zones on the meter's pulse" do
    assert zone(@six_eight, :quarter) == ticks(:eighth)
    assert zone(@four_four, :eighth, 1) == ticks(:quarter)
  end

  test "a beat or longer: one zone per beat" do
    assert zone(@twelve_eight, :quarter, 1) == ticks(:quarter, 1)
    assert zone(@twelve_eight, :half, 1) == ticks(:quarter, 1)
    assert zone(@four_four, :half) == ticks(:quarter)
    assert zone(@four_four, :quarter, 1) == ticks(:quarter)
    assert zone(@four_four, :whole) == ticks(:quarter)
  end

  test "the bar has as many zones as the plan says" do
    assert zones(@twelve_eight, :eighth) == 12
    assert zones(@four_four, :eighth) == 8
    assert zones(@twelve_eight, :quarter, 1) == 4
    assert zones(@four_four, :half) == 4
  end

  defp ticks(value, dots \\ 0), do: Duration.ticks(value, dots)

  defp zone(ctx, value, dots \\ 0), do: Context.zone_ticks(ctx, ticks(value, dots))

  defp zones(ctx, value, dots \\ 0), do: div(Context.measure_ticks(ctx), zone(ctx, value, dots))
end
