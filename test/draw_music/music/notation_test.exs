defmodule DrawMusic.Music.NotationTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Accidentals, Beaming, Context, Measure, Note, Rest, Stems}

  defp note(spn, offset, attrs \\ %{}) do
    {step, alter} = pitch!(spn)

    struct!(
      %Note{id: Ecto.UUID.generate(), staff: :treble, voice: 1, value: :eighth, dots: 0},
      Map.merge(%{offset: offset, step: step, alter: alter}, attrs)
    )
  end

  defp eighths(offsets, attrs \\ %{}), do: Enum.map(offsets, &note("C5", &1, attrs))

  defp offsets(groups), do: Enum.map(groups, & &1.offsets)

  defp step(spn), do: elem(pitch!(spn), 0)

  describe "Beaming.groups/3" do
    test "groups eighths by the beat in simple meters" do
      measure = %Measure{notes: eighths([0, 480, 960, 1440, 1920]), rests: []}
      assert offsets(Beaming.groups(measure, %Context{}, 0)) == [[0, 480], [960, 1440]]
    end

    test "groups by the dotted quarter in compound meters" do
      measure = %Measure{notes: eighths(Enum.map(0..5, &(&1 * 480))), rests: []}
      six_eight = %Context{time_num: 6, time_den: 8}
      assert offsets(Beaming.groups(measure, six_eight, 0)) == [[0, 480, 960], [1440, 1920, 2400]]
    end

    test "rests and longer notes break a group; a chord counts once" do
      notes = eighths([0, 1440, 1920]) ++ [note("C5", 480, %{value: :quarter})]
      rest = %Rest{staff: :treble, voice: 1, offset: 960, value: :eighth, dots: 0}
      assert Beaming.groups(%Measure{notes: notes, rests: [rest]}, %Context{}, 0) == []

      chord = %Measure{notes: eighths([0, 480]) ++ [note("E5", 0)], rests: []}
      assert offsets(Beaming.groups(chord, %Context{}, 0)) == [[0, 480]]
    end

    test "each voice is beamed separately" do
      measure = %Measure{notes: eighths([0, 480]) ++ eighths([0, 480], %{voice: 2}), rests: []}

      assert [%{voice: 1, offsets: [0, 480]}, %{voice: 2, offsets: [0, 480]}] =
               Beaming.groups(measure, %Context{}, 0)
    end

    test "a pickup's beats are counted back from its end" do
      measure = %Measure{notes: eighths([0, 480, 960]), rests: []}
      ctx = %Context{pickup_ticks: 1440}
      assert offsets(Beaming.groups(measure, ctx, 0)) == [[480, 960]]
    end
  end

  describe "Stems.direction" do
    test "up below the middle line, down on or above it, down when the extremes balance" do
      assert Stems.direction(:treble, [step("C4")]) == :up
      assert Stems.direction(:treble, [step("B4")]) == :down
      assert Stems.direction(:treble, [step("C4"), step("A5")]) == :down
      assert Stems.direction(:bass, [step("E2"), step("G2")]) == :up
    end

    test "with several voices, odd voices stem up and even voices down" do
      high = [step("A5")]
      assert Stems.direction(:treble, high, 1, 2) == :up
      assert Stems.direction(:treble, high, 2, 2) == :down
      assert Stems.direction(:treble, high, 1, 1) == :down
    end
  end

  describe "Accidentals.displayed/3" do
    test "signs show only where the alteration differs from what is in effect" do
      a = note("F#4", 0)
      b = note("F4", 480)
      c = note("F4", 960)
      d = note("F#4", 1440)
      e = note("F5", 1920)
      measure = %Measure{notes: [a, b, c, d, e], rests: []}

      # G major: F♯ is in the key. The natural lasts to the bar line on its
      # own staff position only.
      assert Accidentals.displayed(measure, 1) == %{b.id => 0, d.id => 1, e.id => 0}
    end

    test "an accidental lasts to the bar line, on its own staff only" do
      a = note("C#4", 0)
      b = note("C#4", 480)
      c = note("C#5", 960)
      d = note("C#4", 0, %{staff: :bass})
      measure = %Measure{notes: [a, b, c, d], rests: []}

      assert Accidentals.displayed(measure, 0) == %{a.id => 1, c.id => 1, d.id => 1}
    end

    test "a note tied in from the previous bar shows no sign, and sets what follows" do
      a = note("C#4", 0)
      b = note("C#4", 960)
      measure = %Measure{notes: [a, b], rests: []}
      assert Accidentals.displayed(measure, 0, MapSet.new([a.id])) == %{}
    end
  end
end
