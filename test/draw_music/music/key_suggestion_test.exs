defmodule DrawMusic.Music.KeySuggestionTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, KeyDetection, KeyFit, KeySuggestion, Pitch, Rekey, Score}

  @c_major %Context{sf: 0}

  # Bars of quarter notes on the treble staff, written in C major.
  defp score(bars) do
    Enum.reduce(Enum.with_index(bars), Score.new(length(bars)), fn {bar, index}, score ->
      bar
      |> Enum.with_index()
      |> Enum.reduce(score, fn {spn, beat}, score ->
        attrs = %{staff: :treble, offset: beat * 960, value: :quarter}
        {score, _id} = note!(score, @c_major, index, spn, attrs)
        score
      end)
    end)
  end

  # E♭ major, entered by ear into C major: every E♭, A♭ and B♭ written sharp.
  defp by_ear_in_e_flat do
    score([
      ~w(D#4 F4 G4 G#4),
      ~w(A#4 C5 D5 D#5),
      ~w(D#4 G4 A#4 D#5),
      ~w(G#4 G4 F4 D#4)
    ])
  end

  describe "Rekey.to_signature/2" do
    test "keeps every pitch and rhythm, spelled for the new key" do
      score = by_ear_in_e_flat()
      rekeyed = Rekey.to_signature(score, -3)

      assert [{0, 0, "E♭4", :quarter, 0}, {0, 960, "F4", :quarter, 0} | _rest] = notes(rekeyed)
      assert {1, 0, "B♭4", :quarter, 0} in notes(rekeyed)

      sounding = fn score ->
        for m <- score.measures, n <- m.notes, do: {n.id, Pitch.midi(n.step, n.alter)}
      end

      assert sounding.(rekeyed) == sounding.(score)
    end
  end

  describe "KeyDetection.ranked/1" do
    test "ranks all 24 keys, best first, led by the detected key" do
      # C, E, G and C: the C major chord.
      notes = for midi <- [60, 64, 67, 72], do: {midi, 960}
      ranked = KeyDetection.ranked(notes)

      assert length(ranked) == 24
      assert Enum.map(ranked, &elem(&1, 1)) == Enum.sort(Enum.map(ranked, &elem(&1, 1)), :desc)
      assert elem(hd(ranked), 0) == KeyDetection.detect(notes)
    end
  end

  describe "suggest/2" do
    test "offers the key the accidentals point to, writing far fewer" do
      suggestion = KeySuggestion.suggest(by_ear_in_e_flat(), {0, :major})

      assert suggestion.worth_it?
      # Nine sharps, and a natural for the G after G♯ in the last bar.
      assert suggestion.accidentals == 10
      assert [%KeyFit{sf: -3, accidentals: 0} | _others] = suggestion.keys
      assert length(suggestion.keys) <= 4
      assert Enum.all?(suggestion.keys, &(&1.accidentals < suggestion.accidentals))

      order = Enum.map(suggestion.keys, &{&1.accidentals, -&1.fit})
      assert order == Enum.sort(order)
    end

    test "offers nothing for music already at home in its key" do
      suggestion = KeySuggestion.suggest(score([~w(C4 D4 E4 F4), ~w(G4 A4 B4 C5)]), {0, :major})

      refute suggestion.worth_it?
      assert suggestion.keys == []
    end

    # Three bars heard in C minor, written in C major: D♯, G♯ then G♮, B♯.
    test "offers a key for a short piece with a handful of accidentals" do
      score = score([~w(G3 D4 D4 D#4), ~w(G#3 G#3 G3 D4), ~w(D4 B#3 F3 F3)])
      suggestion = KeySuggestion.suggest(score, {0, :major})

      assert suggestion.accidentals == 4
      assert suggestion.worth_it?
      # The fewest accidentals first: C minor's three flats leave none.
      assert [%KeyFit{sf: -3, accidentals: 0, accidental_notes: []} | _others] = suggestion.keys

      # G minor's two flats leave the A♭s, named once.
      assert %KeyFit{accidentals: 1, accidental_notes: ["A♭"]} =
               Enum.find(suggestion.keys, &(&1.sf == -2 and &1.mode == :minor))
    end

    test "offers no key whose accidentals are more than two different notes" do
      suggestion = KeySuggestion.suggest(by_ear_in_e_flat(), {0, :major})

      assert Enum.all?(suggestion.keys, &(length(&1.accidental_notes) <= 2))
    end

    test "is not worth it for a single accidental" do
      suggestion = KeySuggestion.suggest(score([~w(C4 D4 E4 F#4), ~w(G4 A4 B4 C5)]), {0, :major})

      refute suggestion.worth_it?
    end
  end
end
