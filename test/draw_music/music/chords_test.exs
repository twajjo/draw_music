defmodule DrawMusic.Music.ChordsTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.Chords

  test "quality_of names every catalog chord it is given back" do
    {root_step, root_alter} = pitch!("D4")

    for quality <- Chords.qualities() do
      {:ok, pitches} = Chords.build(root_step, root_alter, quality)
      assert Chords.quality_of(pitches) == quality
    end
  end

  test "quality_of is nil for a stack that isn't in the catalog" do
    assert Chords.quality_of([pitch!("C4"), pitch!("D4"), pitch!("E4")]) == nil
  end

  test "lead-sheet suffixes: major is the root alone, minor adds m" do
    assert Chords.suffix(:major) == ""
    assert Chords.suffix(:minor) == "m"
    assert Chords.suffix(:half_diminished7) == "m7♭5"
  end

  test "numerals follow the mode" do
    assert Chords.numeral(:major, 2) == "ii"
    assert Chords.numeral(:minor, 5) == "V"
    assert Chords.numeral(:minor, 2) == "ii°"
  end
end
