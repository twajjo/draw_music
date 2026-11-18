defmodule DrawMusic.Music.TimelineTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.Timeline

  # A bar of 4/4 (3,840 ticks) after a one-beat pickup.
  @bars [{0, 960}, {960, 3840}]

  test "the bar holding a tick, none past the last" do
    assert Timeline.bar_at(@bars, 0) == {0, 960}
    assert Timeline.bar_at(@bars, 960) == {960, 3840}
    assert Timeline.bar_at(@bars, 4799) == {960, 3840}
    assert Timeline.bar_at(@bars, 4800) == nil
  end

  test "a length fits a bar when it starts and ends inside it" do
    assert Timeline.fits?({960, 3840}, 960, 3840)
    refute Timeline.fits?({960, 3840}, 960, 3841)
    refute Timeline.fits?({960, 3840}, 0, 960)
    refute Timeline.fits?(nil, 0, 1)
  end
end
