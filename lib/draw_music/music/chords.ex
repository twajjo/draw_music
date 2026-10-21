defmodule DrawMusic.Music.Chords do
  @moduledoc """
  The chord catalog: chords built up from a root as `{step, alter}` lists,
  spelled by letter (stacked thirds) so a D minor 7th is D F A C.
  """

  alias DrawMusic.Music.Pitch

  # {steps above root, semitones above root}
  @qualities %{
    major: [{0, 0}, {2, 4}, {4, 7}],
    minor: [{0, 0}, {2, 3}, {4, 7}],
    diminished: [{0, 0}, {2, 3}, {4, 6}],
    augmented: [{0, 0}, {2, 4}, {4, 8}],
    dominant7: [{0, 0}, {2, 4}, {4, 7}, {6, 10}],
    major7: [{0, 0}, {2, 4}, {4, 7}, {6, 11}],
    minor7: [{0, 0}, {2, 3}, {4, 7}, {6, 10}],
    half_diminished7: [{0, 0}, {2, 3}, {4, 6}, {6, 10}],
    diminished7: [{0, 0}, {2, 3}, {4, 6}, {6, 9}],
    sus2: [{0, 0}, {1, 2}, {4, 7}],
    sus4: [{0, 0}, {3, 5}, {4, 7}],
    add9: [{0, 0}, {2, 4}, {4, 7}, {8, 14}]
  }

  def qualities, do: Map.keys(@qualities)

  @doc "Builds a chord of `quality` on the root `{root_step, root_alter}`."
  def build(root_step, root_alter, quality) do
    root = Pitch.midi(root_step, root_alter)

    @qualities
    |> Map.fetch!(quality)
    |> Enum.map(fn {steps, semis} ->
      step = root_step + steps
      {step, root + semis - Pitch.natural_midi(step)}
    end)
    |> checked()
  end

  @doc """
  The chord the key itself builds on `root_step`: a triad (or seventh chord
  with `seventh: true`) of the key's notes. In minor keys the V and vii°
  chords raise the leading tone, as in harmonic minor.
  """
  def diatonic(sf, mode, root_step, opts \\ []) do
    {tonic, _pc} = Pitch.tonic(sf, mode)
    degree = Integer.mod(Pitch.letter(root_step) - tonic, 7) + 1
    size = if Keyword.get(opts, :seventh, false), do: 4, else: 3

    for k <- 0..(size - 1) do
      step = root_step + 2 * k
      letter = Pitch.letter(step)
      {step, Pitch.key_alter(sf, letter) + leading_tone(mode, degree, letter, tonic)}
    end
    |> checked()
  end

  defp leading_tone(:minor, degree, letter, tonic) when degree in [5, 7],
    do: if(Integer.mod(letter - tonic, 7) == 6, do: 1, else: 0)

  defp leading_tone(_mode, _degree, _letter, _tonic), do: 0

  defp checked(pitches) do
    if Enum.all?(pitches, fn {step, alter} ->
         alter in -2..2 and Pitch.in_range?(Pitch.midi(step, alter))
       end),
       do: {:ok, pitches},
       else: {:error, :out_of_range}
  end
end
