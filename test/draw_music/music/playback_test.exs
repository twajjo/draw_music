defmodule DrawMusic.Music.PlaybackTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Playback, Score}

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
end
