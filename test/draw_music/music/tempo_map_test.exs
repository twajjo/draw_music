defmodule DrawMusic.Music.TempoMapTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Score, TempoChange, TempoMap}

  # 960 ticks a quarter; tempos count quarters per minute.
  @quarter 960

  defp map(tempos, bpm \\ 60),
    do: TempoMap.new(%Score{Score.new() | tempos: tempos}, %Context{tempo_bpm: bpm})

  defp mark(tick, bpm), do: %TempoChange{tick: tick, bpm: bpm}

  defp ramp(tick, bpm, to_tick, to_bpm),
    do: %TempoChange{tick: tick, bpm: bpm, to_tick: to_tick, to_bpm: to_bpm}

  test "with no changes, the starting tempo throughout" do
    assert_in_delta TempoMap.seconds(map([], 100), 0, @quarter), 0.6, 1.0e-9
    assert_in_delta TempoMap.seconds(map([], 100), @quarter, 3 * @quarter), 1.2, 1.0e-9
  end

  test "a mark changes the speed from its tick on" do
    tempos = [mark(@quarter, 120)]
    # One quarter at 60 (1 s), then one at 120 (0.5 s).
    assert_in_delta TempoMap.seconds(map(tempos), 0, 2 * @quarter), 1.5, 1.0e-9
    assert_in_delta TempoMap.seconds(map(tempos), @quarter, 2 * @quarter), 0.5, 1.0e-9
  end

  test "marks may come in any order" do
    tempos = [mark(2 * @quarter, 30), mark(@quarter, 120)]
    assert_in_delta TempoMap.seconds(map(tempos), 0, 3 * @quarter), 1 + 0.5 + 2, 1.0e-9
  end

  # Speeding evenly from 60 to 120 over a quarter takes ln 2 seconds, not
  # the 0.667 s of averaging the two speeds; then it stays at 120.
  test "an accelerando is timed exactly, and holds its end tempo" do
    tempos = [ramp(0, 60, @quarter, 120)]
    assert_in_delta TempoMap.seconds(map(tempos), 0, @quarter), :math.log(2), 1.0e-9
    assert_in_delta TempoMap.seconds(map(tempos), @quarter, 2 * @quarter), 0.5, 1.0e-9
  end

  test "a change part-way through a ritardando takes over there" do
    tempos = [ramp(0, 120, 2 * @quarter, 60), mark(@quarter, 120)]
    # Slowing from 120 for half its span reaches 90 at the mark.
    slowing = 60 / (@quarter * (-60 / (2 * @quarter))) * :math.log(90 / 120)
    assert_in_delta TempoMap.seconds(map(tempos), 0, @quarter), slowing, 1.0e-9
    assert_in_delta TempoMap.seconds(map(tempos), @quarter, 2 * @quarter), 0.5, 1.0e-9
  end

  test "anchors pair each tempo change and each beat of a ramp with its time" do
    tempos = [mark(@quarter, 120), ramp(2 * @quarter, 120, 4 * @quarter, 60)]
    anchors = TempoMap.anchors(map(tempos), 0, 6 * @quarter)

    assert Enum.map(anchors, & &1.tick) == [0, 1, 2, 3, 4, 6] |> Enum.map(&(&1 * @quarter))
    assert hd(anchors).seconds == 0.0

    for anchor <- anchors do
      assert_in_delta anchor.seconds, TempoMap.seconds(map(tempos), 0, anchor.tick), 1.0e-9
    end
  end

  test "anchors are timed from where playback starts" do
    anchors = TempoMap.anchors(map([mark(2 * @quarter, 120)]), @quarter, 3 * @quarter)

    assert Enum.map(anchors, &{&1.tick, Float.round(&1.seconds, 9)}) == [
             {960, 0.0},
             {1920, 1.0},
             {2880, 1.5}
           ]
  end
end
