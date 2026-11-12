defmodule DrawMusic.Music.TempoMarkingTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Context, TempoMarking}

  test "each word belongs to one marking only, so a stored word tells its marking" do
    words = TempoMarking.all()
    assert words == Enum.uniq(words)
  end

  test "every marking has an English word, which gives its meaning" do
    for {_title, markings} <- TempoMarking.sections(), marking <- markings do
      assert is_binary(marking.english)
    end
  end

  test "markings by speed suggest tempos in range, rising down the list" do
    [{"By speed", by_speed}, {"By character", by_character}] = TempoMarking.sections()
    bpms = Enum.map(by_speed, & &1.bpm)

    assert Enum.all?(bpms, &(&1 in Context.tempo_range()))
    assert bpms == Enum.sort(bpms)

    for %{bpm: bpm} <- by_character, bpm, do: assert(bpm in Context.tempo_range())
  end

  test "a new score's marking suggests its starting tempo" do
    assert TempoMarking.find(TempoMarking.default()).bpm == %Context{}.tempo_bpm
  end

  test "a word finds its marking, in any language" do
    allegro = TempoMarking.find("Allegro")

    assert TempoMarking.find("Schnell") == allegro
    assert TempoMarking.find("Fast") == allegro
    assert TempoMarking.find("Zippy") == nil
  end

  test "another marking keeps the printed language, where it has a word in it" do
    lento = TempoMarking.find("Lento")
    larghissimo = TempoMarking.find("Larghissimo")

    assert TempoMarking.word_for(lento, "Vite") == "Lent"
    assert TempoMarking.word_for(lento, "Lento") == "Lento"
    assert TempoMarking.word_for(larghissimo, "Schnell") == "Larghissimo"
    assert TempoMarking.word_for(lento, nil) == "Lento"
  end
end
