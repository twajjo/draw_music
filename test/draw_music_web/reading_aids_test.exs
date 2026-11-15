defmodule DrawMusicWeb.ReadingAidsTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Accounts.User
  alias DrawMusic.Engraving.{Engraved, Layout, System}
  alias DrawMusic.Music.{Context, Score}
  alias DrawMusicWeb.{ReadingAid, ReadingAids}

  # The letters of one kind, top to bottom, for the staff whose part of the
  # system (by y) `in_staff?` picks.
  defp letters(kind, in_staff?) do
    for %ReadingAid{kind: ^kind, y: y, text: text} <-
          Enum.sort_by(ReadingAids.staff_letters(), & &1.y),
        in_staff?.(y),
        do: text
  end

  defp treble?(y), do: y <= 4
  defp bass?(y), do: y >= 12

  test "each staff's lines and spaces are lettered, top to bottom" do
    assert letters(:line, &treble?/1) == ~w(F D B G E)
    assert letters(:space, &treble?/1) == ~w(E C A F)
    assert letters(:line, &bass?/1) == ~w(A F D B G)
    assert letters(:space, &bass?/1) == ~w(G E C A)
  end

  test "middle C is marked below the treble and above the bass" do
    assert [below_treble, above_bass] =
             for(%ReadingAid{kind: :middle_c} = c <- ReadingAids.staff_letters(), do: c)
             |> Enum.sort_by(& &1.y)

    assert below_treble.y > 4 and above_bass.y < 12
    assert below_treble.text == "C" and above_bass.text == "C"
  end

  # In G major: F♯ (the key's), F♮ (written), F♯ again (written), then a C.
  test "every note is named as it sounds, with ♮ only where one is written" do
    ctx = %Context{sf: 1}
    notes = [{"F#4", 0}, {"F4", 960}, {"F#4", 1920}, {"C5", 2880}]

    score =
      Enum.reduce(notes, Score.new(1), fn {spn, offset}, score ->
        {score, _id} =
          note!(score, ctx, 0, spn, %{staff: :treble, offset: offset, value: :quarter})

        score
      end)

    [system] = Layout.layout(score, ctx, width: 60).systems
    names = system.items |> ReadingAids.note_names(:when_selected) |> Enum.sort_by(& &1.x)

    assert Enum.map(names, & &1.text) == ~w(F♯ F♮ F♯ C)
    assert Enum.all?(names, &(&1.kind == :note and &1.shown == :when_selected))
    assert names |> Enum.map(& &1.note_id) |> Enum.uniq() |> length() == 4
  end

  test "added to every line of music only when the user wants them" do
    system = fn index ->
      %System{index: index, width: 10.0, measures: [], items: []}
    end

    engraved = %Engraved{width: 10.0, height: 30.0, systems: [system.(0), system.(1)]}

    assert ReadingAids.add(engraved, %User{letter_staves: false}) == engraved

    for %System{items: items} <- ReadingAids.add(engraved, %User{letter_staves: true}).systems do
      assert length(items) == length(ReadingAids.staff_letters())
    end
  end
end
