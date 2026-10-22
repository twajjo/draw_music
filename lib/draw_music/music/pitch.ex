defmodule DrawMusic.Music.Pitch do
  @moduledoc """
  Pitch arithmetic and scientific pitch notation (SPN).

  A written note is a `step` (diatonic staff position: `octave * 7 + letter`,
  letters C=0 … B=6, so middle C4 is step 28) and an absolute `alter` in
  semitones (-2..2: 𝄫, ♭, ♮, ♯, 𝄪). Its sounding pitch is a MIDI number
  (C4 = 60). The playable range is the piano's, A0 (21) to C8 (108).

  In SPN a note is letter + accidental + octave, e.g. `"C♯4"`; octave
  numbers change at C, so B3 is the note just below C4.

  Key signatures are `sf` as MIDI stores them: -7..-1 flats, 1..7 sharps.
  """

  @semis {0, 2, 4, 5, 7, 9, 11}
  @letter_names {"C", "D", "E", "F", "G", "A", "B"}
  @accidental_names %{-2 => "𝄫", -1 => "♭", 0 => "", 1 => "♯", 2 => "𝄪"}
  @accidental_alters %{
    "" => 0,
    "♮" => 0,
    "#" => 1,
    "♯" => 1,
    "##" => 2,
    "x" => 2,
    "𝄪" => 2,
    "b" => -1,
    "♭" => -1,
    "bb" => -2,
    "𝄫" => -2
  }
  # F C G D A E B, and B E A D G C F, as letter numbers.
  @sharp_order [3, 0, 4, 1, 5, 2, 6]
  @flat_order [6, 2, 5, 1, 4, 0, 3]

  @min_midi 21
  @max_midi 108

  @spec min_midi() :: 21
  def min_midi, do: @min_midi
  @spec max_midi() :: 108
  def max_midi, do: @max_midi
  @spec in_range?(integer()) :: boolean()
  def in_range?(midi), do: midi in @min_midi..@max_midi

  @spec letter(integer()) :: 0..6
  def letter(step), do: Integer.mod(step, 7)
  @spec octave(integer()) :: integer()
  def octave(step), do: Integer.floor_div(step, 7)
  @spec step(0..6, integer()) :: integer()
  def step(letter, octave), do: octave * 7 + letter

  @doc "MIDI number of the step with no accidental."
  @spec natural_midi(integer()) :: integer()
  def natural_midi(step), do: 12 * (octave(step) + 1) + elem(@semis, letter(step))

  @spec midi(integer(), integer()) :: integer()
  def midi(step, alter), do: natural_midi(step) + alter

  @doc "Equal-tempered frequency in Hz, A4 = 440."
  @spec frequency(number()) :: float()
  def frequency(midi), do: 440.0 * :math.pow(2, (midi - 69) / 12)

  @doc "SPN name, e.g. `name(28, 1)` → `\"C♯4\"`."
  @spec name(integer(), integer()) :: String.t()
  def name(step, alter) do
    elem(@letter_names, letter(step)) <>
      Map.fetch!(@accidental_names, alter) <>
      Integer.to_string(octave(step))
  end

  @doc """
  Parses SPN into `{:ok, {step, alter}}`. Accepts Unicode accidentals
  (♯ ♭ 𝄪 𝄫 ♮) and ASCII ones (`#`, `b`, `##`/`x`, `bb`), e.g. `"Bb3"`.
  """
  @spec parse(String.t()) :: {:ok, {integer(), -2..2}} | {:error, :invalid_pitch}
  def parse(name) when is_binary(name) do
    with [_, letter, accidental, octave] <-
           Regex.run(~r/^([A-Ga-g])(##|#|♯|x|𝄪|bb|b|♭|𝄫|♮)?(-?\d)$/u, String.trim(name)),
         letter_index when is_integer(letter_index) <- letter_index(letter) do
      {:ok,
       {step(letter_index, String.to_integer(octave)), Map.fetch!(@accidental_alters, accidental)}}
    else
      _ -> {:error, :invalid_pitch}
    end
  end

  defp letter_index(letter) do
    Enum.find_index(Tuple.to_list(@letter_names), &(&1 == String.upcase(letter)))
  end

  @doc "The alteration the key signature `sf` gives `letter`: -1, 0 or 1."
  @spec key_alter(-7..7, 0..6) :: -1..1
  def key_alter(sf, letter) when sf > 0,
    do: if(letter in Enum.take(@sharp_order, sf), do: 1, else: 0)

  def key_alter(sf, letter) when sf < 0,
    do: if(letter in Enum.take(@flat_order, -sf), do: -1, else: 0)

  def key_alter(0, _letter), do: 0

  @doc "Tonic of a key as `{letter, pitch_class}`, e.g. `tonic(-1, :minor)` is D."
  @spec tonic(-7..7, :major | :minor) :: {0..6, 0..11}
  def tonic(sf, :major), do: {Integer.mod(4 * sf, 7), Integer.mod(7 * sf, 12)}
  def tonic(sf, :minor), do: {Integer.mod(5 + 4 * sf, 7), Integer.mod(9 + 7 * sf, 12)}

  @doc """
  Spells a MIDI number as `{step, alter}` for key signature `sf`: the key's
  own note when there is one, otherwise a natural, otherwise sharps in sharp
  keys and flats in flat keys.
  """
  @spec spell(integer(), -7..7) :: {integer(), -2..2}
  def spell(midi, sf) do
    pc = Integer.mod(midi, 12)

    {letter, alter} =
      for letter <- 0..6,
          alter <- -2..2,
          Integer.mod(elem(@semis, letter) + alter, 12) == pc do
        {letter, alter}
      end
      |> Enum.min_by(&spelling_cost(&1, sf))

    octave = div(midi - alter - elem(@semis, letter), 12) - 1
    {step(letter, octave), alter}
  end

  defp spelling_cost({letter, alter}, sf) do
    if alter == key_alter(sf, letter) do
      0
    else
      1 + 2 * abs(alter) + against_key(alter, sf)
    end
  end

  defp against_key(alter, sf) when alter > 0 and sf < 0, do: 1
  defp against_key(alter, sf) when alter < 0 and sf >= 0, do: 1
  defp against_key(_alter, _sf), do: 0
end
