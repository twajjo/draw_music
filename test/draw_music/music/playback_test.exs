defmodule DrawMusic.Music.PlaybackTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Playback, Score, Timeline}

  describe "chord_at/3" do
    setup do
      ctx = %Context{sf: 1}
      quarter = fn offset, staff -> %{staff: staff, offset: offset, value: :quarter} end

      {score, _g} = note!(Score.new(2), ctx, 0, "G4", quarter.(0, :treble))
      {score, b} = note!(score, ctx, 0, "B4", quarter.(0, :treble))
      {score, _d} = note!(score, ctx, 0, "D5", quarter.(0, :treble))
      {score, _bass} = note!(score, ctx, 0, "G2", quarter.(0, :bass))
      {score, f} = note!(score, ctx, 0, "F#4", quarter.(960, :treble))

      {:ok, score, rest} =
        Editing.place_rest(score, ctx, 0, placement(nil, quarter.(1920, :treble)))

      %{ctx: ctx, score: score, b: b, f: f, rest: rest}
    end

    test "sounds the chord on one staff, from the start", %{ctx: ctx, score: score, b: b} do
      events = Playback.chord_at(score, ctx, b)

      assert events |> Enum.map(& &1.midi) |> Enum.sort() == [67, 71, 74]
      assert Enum.all?(events, &(&1.start == 0.0))
    end

    test "a lone note sounds alone, with its spelling", %{ctx: ctx, score: score, f: f} do
      assert [%{midi: 66}] = Playback.chord_at(score, ctx, f)
    end

    test "a rest or an unknown id sounds nothing", %{ctx: ctx, score: score, rest: rest} do
      assert Playback.chord_at(score, ctx, rest) == []
      assert Playback.chord_at(score, ctx, Ecto.UUID.generate()) == []
    end
  end

  describe "span/3, first_event_from/3 and skip_target/3" do
    setup do
      ctx = %Context{}
      quarter = fn offset -> %{staff: :treble, offset: offset, value: :quarter} end

      {score, c} = note!(Score.new(2), ctx, 0, "C4", quarter.(0))
      {score, e} = note!(score, ctx, 0, "E4", quarter.(1920))

      %{ctx: ctx, score: score, c: c, e: e, end_tick: Timeline.end_tick(score, ctx)}
    end

    test "with nothing selected, Play plays the whole score", %{ctx: ctx, score: score} = s do
      assert Playback.span(score, ctx, MapSet.new()) == {0, s.end_tick}
    end

    test "one selected event plays from there to the end", %{ctx: ctx, score: score, e: e} = s do
      assert Playback.span(score, ctx, MapSet.new([e])) == {1920, s.end_tick}
    end

    test "several play from the first to the end of the last", %{ctx: ctx, score: score} = s do
      assert Playback.span(score, ctx, MapSet.new([s.c, s.e])) == {0, 2880}
    end

    test "the first event at or after a tick", %{ctx: ctx, score: score, e: e} do
      assert Playback.first_event_from(score, ctx, 1920) == e
      assert Playback.first_event_from(score, ctx, 1000) == e
      assert Playback.first_event_from(score, ctx, 99_999) == nil
    end

    test "a skip lands on the next point, or going back on the previous one" do
      points = [0, 3840, 7680]

      assert Playback.skip_target(points, 100, false) == 3840
      assert Playback.skip_target(points, 3840, true) == 0
      assert Playback.skip_target(points, 7680, false) == nil
      assert Playback.skip_target(points, 0, true) == nil
    end
  end
end
