defmodule DrawMusicWeb.EditorGeometryTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.Context
  alias DrawMusicWeb.{Armed, EditorGeometry}
  alias DrawMusicWeb.EditorGeometry.ChordShape

  defp chord(chord), do: %Armed{kind: :chord, value: :quarter, chord: chord}

  test "a chord quality sends its intervals above the root and its suffix" do
    payload = EditorGeometry.armed(chord({:quality, :minor}), %Context{})

    assert %ChordShape{
             kind: :quality,
             tones: [[0, 0], [2, 3], [4, 7]],
             suffix: "m",
             numeral: nil
           } = payload.chord
  end

  test "a scale degree sends the key's chord on that letter, and its numeral" do
    payload = EditorGeometry.armed(chord({:degree, 2}), %Context{sf: 0, mode: :major})

    assert %ChordShape{
             kind: :degree,
             root_letter: 1,
             tones: [[0, 0], [2, 0], [4, 0]],
             suffix: "m",
             numeral: "ii"
           } = payload.chord
  end

  test "in a minor key, V raises the leading tone" do
    payload = EditorGeometry.armed(chord({:degree, 5}), %Context{sf: 0, mode: :minor})

    assert %ChordShape{root_letter: 2, tones: [[0, 0], [2, 1], [4, 0]], suffix: "", numeral: "V"} =
             payload.chord
  end

  test "a single note sends no chord" do
    payload = EditorGeometry.armed(%Armed{kind: :note, value: :quarter}, %Context{})
    assert payload.chord == nil
  end
end
