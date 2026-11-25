defmodule DrawMusicWeb.EditorPaletteBeatTest do
  @moduledoc "The value that is one beat in the meter, which the palette marks and B arms."
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias DrawMusic.Music.{Context, KeySuggestion}
  alias DrawMusicWeb.{Armed, EditorPalette}
  alias DrawMusicWeb.Palette.EditTools

  test "one beat is the beat felt in the bar" do
    assert EditorPalette.beat(%Context{}) == {:quarter, 0}
    assert EditorPalette.beat(%Context{time_num: 3, time_den: 4}) == {:quarter, 0}
    assert EditorPalette.beat(%Context{time_num: 2, time_den: 2}) == {:half, 0}
    assert EditorPalette.beat(%Context{time_num: 3, time_den: 8}) == {:eighth, 0}

    for num <- [6, 9, 12] do
      assert EditorPalette.beat(%Context{time_num: num, time_den: 8}) == {:quarter, 1}
    end
  end

  test "the Beat sign shows the beat's value with its dots; the buttons stay unmarked" do
    dotted = durations({:quarter, 1})

    assert LazyHTML.query(dotted, "#palette-beat[data-value=quarter][data-dots='1'] .beat-dot")
           |> Enum.count() == 1

    assert LazyHTML.query(dotted, "#palette-quarter[title*='beat']") |> Enum.empty?()

    plain = durations({:half, 0})

    assert plain
           |> LazyHTML.query("#palette-beat[data-value=half][data-dots='0']")
           |> Enum.count() == 1

    assert LazyHTML.query(plain, "#palette-beat .beat-dot") |> Enum.empty?()
  end

  test "arming the beat gives its value and dots, as the row's kind" do
    assert %Armed{kind: :note, value: :quarter, dots: 1} =
             EditorPalette.arm_beat(nil, :note, {:quarter, 1})

    assert %Armed{kind: :rest, value: :half, dots: 0} =
             EditorPalette.arm_beat(nil, :rest, {:half, 0})
  end

  test "an armed note keeps its accidental; a chord becomes a beat long" do
    sharp = %Armed{kind: :note, value: :quarter, alter: 1}
    assert %Armed{alter: 1, dots: 1} = EditorPalette.arm_beat(sharp, :note, {:quarter, 1})

    chord = %Armed{kind: :chord, value: :eighth, chord: {:quality, :major}}

    assert %Armed{kind: :chord, value: :quarter, dots: 1, chord: {:quality, :major}} =
             EditorPalette.arm_beat(chord, :note, {:quarter, 1})
  end

  defp durations(beat) do
    suggestion = %KeySuggestion{accidentals: 0, keys: [], worth_it?: false}

    html = render_component(&EditTools.edit_tools/1, beat: beat, key_suggestion: suggestion)
    LazyHTML.from_fragment(html)
  end
end
