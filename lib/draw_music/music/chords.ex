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

  @steps_per_third 2
  @triad 3
  @seventh_chord 4
  @dominant 5
  @leading_tone 7

  @typedoc "A chord quality from the catalog."
  @type quality ::
          :major
          | :minor
          | :diminished
          | :augmented
          | :dominant7
          | :major7
          | :minor7
          | :half_diminished7
          | :diminished7
          | :sus2
          | :sus4
          | :add9

  @typedoc "A pitch as a staff step and an alteration."
  @type pitch :: {integer(), -2..2}

  # Lead-sheet chord-name endings: a major chord is the root alone.
  @suffixes %{
    major: "",
    minor: "m",
    diminished: "dim",
    augmented: "aug",
    dominant7: "7",
    major7: "maj7",
    minor7: "m7",
    half_diminished7: "m7♭5",
    diminished7: "dim7",
    sus2: "sus2",
    sus4: "sus4",
    add9: "add9"
  }

  @numerals %{
    major: ~w(I ii iii IV V vi vii°),
    minor: ~w(i ii° III iv V VI vii°)
  }

  @doc "The chord qualities in the catalog."
  @spec qualities() :: [quality()]
  def qualities, do: Map.keys(@qualities)

  @doc "A quality's chord-name ending, e.g. `\"m\"` in Cm (none for major)."
  @spec suffix(quality()) :: String.t()
  def suffix(quality), do: Map.fetch!(@suffixes, quality)

  @doc "The roman numeral of scale degree `degree` (1..7) in a major or minor key."
  @spec numeral(:major | :minor, 1..7) :: String.t()
  def numeral(mode, degree), do: Enum.at(Map.fetch!(@numerals, mode), degree - 1)

  @doc "The numerals of a mode's seven degrees, in order."
  @spec numerals(:major | :minor) :: [String.t()]
  def numerals(mode), do: Map.fetch!(@numerals, mode)

  @doc """
  The catalog quality of a chord given root first, by the letter steps and
  semitones of each note above the root; nil when it isn't in the catalog.
  """
  @spec quality_of([pitch()]) :: quality() | nil
  def quality_of([{root_step, root_alter} | _] = pitches) do
    root = Pitch.midi(root_step, root_alter)

    shape =
      Enum.map(pitches, fn {step, alter} -> {step - root_step, Pitch.midi(step, alter) - root} end)

    Enum.find_value(@qualities, fn
      {quality, ^shape} -> quality
      _other -> nil
    end)
  end

  @doc "A quality's notes as {letter steps, semitones} above the root."
  @spec intervals(quality()) :: [{non_neg_integer(), non_neg_integer()}]
  def intervals(quality), do: Map.fetch!(@qualities, quality)

  @doc "Builds a chord of `quality` on the root `{root_step, root_alter}`."
  @spec build(integer(), -2..2, quality()) :: {:ok, [pitch()]} | {:error, :out_of_range}
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
  @spec diatonic(-7..7, :major | :minor, integer()) :: {:ok, [pitch()]} | {:error, :out_of_range}
  @spec diatonic(-7..7, :major | :minor, integer(), seventh: boolean()) ::
          {:ok, [pitch()]} | {:error, :out_of_range}
  def diatonic(sf, mode, root_step, opts \\ []) do
    {tonic, _pc} = Pitch.tonic(sf, mode)
    degree_of = &(Integer.mod(Pitch.letter(&1) - tonic, Pitch.steps_per_octave()) + 1)
    root_degree = degree_of.(root_step)

    for third <- 0..(chord_size(Keyword.get(opts, :seventh, false)) - 1) do
      step = root_step + @steps_per_third * third
      key_alter = Pitch.key_alter(sf, Pitch.letter(step))
      {step, key_alter + harmonic_minor_raise(mode, root_degree, degree_of.(step))}
    end
    |> checked()
  end

  defp chord_size(true = _seventh?), do: @seventh_chord
  defp chord_size(false), do: @triad

  defp harmonic_minor_raise(:minor, root_degree, @leading_tone)
       when root_degree in [@dominant, @leading_tone] do
    1
  end

  defp harmonic_minor_raise(_mode, _root_degree, _degree), do: 0

  defp checked(pitches) do
    case Enum.reject(pitches, fn {step, alter} -> Pitch.playable?(step, alter) end) do
      [] -> {:ok, pitches}
      _out_of_range -> {:error, :out_of_range}
    end
  end
end
