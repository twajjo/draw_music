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

  @semitones Pitch.semitones_per_octave()
  @steps Pitch.steps_per_octave()
  @middle_c Pitch.middle_c()

  @doc "The score with every note spelled for key signature `sf`."
  @spec to_signature(Score.t(), -7..7) :: Score.t()
  def to_signature(%Score{measures: measures} = score, sf) do
    spellings = spellings(sf)
    %{score | measures: Enum.map(measures, &respell(&1, spellings))}
  end

  defp respell(%Measure{notes: notes} = measure, spellings) do
    %{measure | notes: Enum.map(notes, &respell_note(&1, spellings))}
  end

  # A note is spelled as its pitch class is around middle C, moved by whole
  # octaves.
  defp respell_note(note, spellings) do
    midi = Pitch.midi(note.step, note.alter)
    pitch_class = Integer.mod(midi, @semitones)
    octaves = div(midi - (@middle_c + pitch_class), @semitones)
    {step, alter} = Map.fetch!(spellings, pitch_class)
    %{note | step: step + octaves * @steps, alter: alter}
  end

  # Each pitch class's spelling in key signature `sf`, around middle C:
  # spelled once per pitch class, not once per note.
  defp spellings(sf) do
    Map.new(0..(@semitones - 1), &{&1, Pitch.spell(@middle_c + &1, sf)})
  end
end
