defmodule DrawMusic.Music.SpansTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Entry, Rest, Spans}

  test "the cursor leaves a note at its end and a rest at its start" do
    items = [{:note, 0, 960}, {:rest, 960, 1920}]

    assert Spans.cursor(items, 480) == 960
    assert Spans.cursor(items, 1440) == 960
    assert Spans.cursor(items, 960) == 960
  end

  test "spans merge where they overlap or touch, and a cover cuts one in two" do
    assert Spans.merge([{480, 960}, {0, 480}, {1000, 1200}]) == [{0, 960}, {1000, 1200}]
    assert Spans.cut_out({200, 300}, [{0, 960}]) == [{0, 200}, {300, 960}]
    assert Spans.cut_out({0, 960}, [{100, 200}]) == []
  end

  test "deleting leaves gaps where nothing else still sounds" do
    removed = [entry(0, 960), entry(960, 960)]
    kept = [entry(480, 480)]

    assert Spans.emptied(removed, kept) == [{0, 480}, {960, 1920}]
  end

  test "the mirror sum is the first tick plus the last" do
    assert Spans.mirror_sum([entry(480, 480), entry(960, 960)]) == 480 + 1920
  end

  defp entry(start, ticks) do
    rest = %Rest{staff: :treble, voice: 1, offset: 0, value: :quarter}
    %Entry{kind: :rest, start: start, ticks: ticks, event: rest}
  end
end
