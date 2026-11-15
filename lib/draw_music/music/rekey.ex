defmodule DrawMusic.Music.Rekey do
  @moduledoc """
  Puts a score in another key without changing how it sounds: every note
  keeps its pitch and is spelled afresh for the new key signature
  (`DrawMusic.Music.Pitch.spell/2`). An A♯ written in C major becomes B♭ in
  E♭ major; notes in the new key need no accidental.

  Unlike `DrawMusic.Music.Transpose`, nothing moves: rhythm, ties, voices
  and staves stay as they are (a tie joins notes of one pitch, which are
  spelled alike).
  """

  alias DrawMusic.Music.{Measure, Pitch, Score}

  @doc "The score with every note spelled for key signature `sf`."
  @spec to_signature(Score.t(), -7..7) :: Score.t()
  def to_signature(%Score{measures: measures} = score, sf) do
    %{score | measures: Enum.map(measures, &respell(&1, sf))}
  end

  defp respell(%Measure{notes: notes} = measure, sf) do
    %{measure | notes: Enum.map(notes, &respell_note(&1, sf))}
  end

  defp respell_note(note, sf) do
    {step, alter} = Pitch.spell(Pitch.midi(note.step, note.alter), sf)
    %{note | step: step, alter: alter}
  end
end
