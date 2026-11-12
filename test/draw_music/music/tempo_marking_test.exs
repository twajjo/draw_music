defmodule DrawMusic.Music.TempoMarkingTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.TempoMarking

  test "each word belongs to one marking only, so a stored word tells its marking" do
    words = TempoMarking.all()
    assert words == Enum.uniq(words)
  end

  test "every marking has an English word, which gives its meaning" do
    for {_title, markings} <- TempoMarking.sections(), marking <- markings do
      assert is_binary(marking.english)
    end
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
