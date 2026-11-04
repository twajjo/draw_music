defmodule DrawMusic.Music.TempoEditingTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, Score, TempoChange, TempoEditing}

  @ctx %Context{}
  # Two bars of 4/4: 7680 ticks.
  defp score(tempos \\ []), do: %{Score.new(2) | tempos: tempos}

  defp mark(id, tick, bpm), do: %TempoChange{id: id, tick: tick, bpm: bpm}
  defp ticks(score), do: Enum.map(score.tempos, &{&1.tick, &1.bpm, &1.to_tick})

  test "a new change gets an id and goes in order" do
    {:ok, s} =
      TempoEditing.put(score([mark("a", 3840, 90)]), @ctx, %TempoChange{tick: 960, bpm: 60})

    assert ticks(s) == [{960, 60, nil}, {3840, 90, nil}]
    assert Enum.all?(s.tempos, &is_binary(&1.id))
  end

  test "a change rewrites the one with its id, and replaces another at its tick" do
    s = score([mark("a", 960, 60), mark("b", 1920, 80)])
    {:ok, s} = TempoEditing.put(s, @ctx, mark("a", 1920, 70))
    assert ticks(s) == [{1920, 70, nil}]
    assert hd(s.tempos).id == "a"
  end

  test "changes stay inside the score" do
    assert TempoEditing.put(score(), @ctx, mark("a", 7680, 60)) == {:error, :past_end}
    assert TempoEditing.put(score(), @ctx, mark("a", -1, 60)) == {:error, :past_end}

    ramp = %TempoChange{id: "r", tick: 6720, bpm: 60, to_tick: 9000, to_bpm: 40}
    {:ok, s} = TempoEditing.put(score(), @ctx, ramp)
    assert ticks(s) == [{6720, 60, 7680}]
  end

  test "moving a rit. keeps its length" do
    ramp = %TempoChange{id: "r", tick: 0, bpm: 60, to_tick: 1920, to_bpm: 40}
    {:ok, s} = TempoEditing.move(score([ramp]), @ctx, "r", 960)
    assert ticks(s) == [{960, 60, 2880}]
  end

  test "a rit.'s end moves, but not to or before its start" do
    ramp = %TempoChange{id: "r", tick: 960, bpm: 60, to_tick: 1920, to_bpm: 40}
    {:ok, s} = TempoEditing.resize(score([ramp]), @ctx, "r", 3840)
    assert ticks(s) == [{960, 60, 3840}]

    assert TempoEditing.resize(score([ramp]), @ctx, "r", 960) == {:error, :invalid_tempo}

    assert TempoEditing.resize(score([mark("m", 0, 60)]), @ctx, "m", 960) ==
             {:error, :invalid_tempo}

    assert TempoEditing.move(score(), @ctx, "gone", 0) == {:error, :not_found}
  end

  test "remove takes out the named changes and ignores other ids" do
    s = TempoEditing.remove(score([mark("a", 0, 60), mark("b", 960, 80)]), ["a", "note-id"])
    assert TempoEditing.ids(s) == ["b"]
  end
end
