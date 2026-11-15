defmodule DrawMusicWeb.ReadingAidsTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Accounts.User
  alias DrawMusic.Engraving.{Engraved, System}
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
