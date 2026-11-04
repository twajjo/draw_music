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

  @letter_names {"C", "D", "E", "F", "G", "A", "B"}
  @steps_per_octave tuple_size(@letter_names)
  @semitones_per_octave 12
  @semitones_above_c {0, 2, 4, 5, 7, 9, 11}

  @min_midi 21
  @max_midi 108
  @middle_c 60
  # MIDI octave -1 starts at 0, so octave n's C is 12 * (n + 1).
  @midi_octave_offset 1
  @a4_midi 69
  @a4_hz 440.0

  # Each sharp moves the tonic up a fifth; a minor key's tonic is a major
  # sixth above its relative major's. As {steps, semitones}.
  @fifth {4, 7}
  @relative_minor {5, 9}

  @alters -2..2
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

  letter_index = fn name -> Enum.find_index(Tuple.to_list(@letter_names), &(&1 == name)) end
  @sharp_order Enum.map(~w(F C G D A E B), letter_index)
  @flat_order Enum.map(~w(B E A D G C F), letter_index)

  # {sf, letter} => the alteration that key signature gives the letter,
  # for every altered letter; the rest are natural.
  @key_alters (for sf <- 1..length(@sharp_order),
                   {order, sign} <- [{@sharp_order, 1}, {@flat_order, -1}],
                   letter <- Enum.take(order, sf),
                   into: %{} do
                 {{sign * sf, letter}, sign}
               end)

  # Spelling preference: the key's own note costs nothing; otherwise fewer
  # and smaller accidentals win, and sharps in flat keys (or flats in sharp
  # keys) cost extra.
  @off_key_cost 1
  @cost_per_semitone 2
  @against_key_cost 1

  @spec min_midi() :: 21
  def min_midi, do: @min_midi
  @spec max_midi() :: 108
  def max_midi, do: @max_midi
  @spec middle_c() :: 60
  def middle_c, do: @middle_c
  @spec steps_per_octave() :: 7
  def steps_per_octave, do: @steps_per_octave
  @spec semitones_per_octave() :: 12
  def semitones_per_octave, do: @semitones_per_octave

  @doc "Alterations a written note may carry, double flat to double sharp."
  @spec alters() :: Range.t()
  def alters, do: @alters

  @spec in_range?(integer()) :: boolean()
  def in_range?(midi), do: midi in @min_midi..@max_midi

  @doc "A written pitch with at most a double accidental, within the playable range."
  @spec playable?(integer(), integer()) :: boolean()
  def playable?(step, alter), do: alter in @alters and in_range?(midi(step, alter))

  @doc """
  Moves `{step, alter}` by an exact interval: the letter moves `steps` and
  the alteration makes up `semitones`. A result needing more than a double
  sharp or flat is re-spelled for key signature `sf`.
  """
  @spec transpose(integer(), integer(), integer(), integer(), -7..7) :: {integer(), -2..2}
  def transpose(step, alter, steps, semitones, sf) do
    target = midi(step, alter) + semitones
    moved = step + steps

    case target - natural_midi(moved) do
      moved_alter when moved_alter in @alters -> {moved, moved_alter}
      _too_far -> spell(target, sf)
    end
  end

  @spec letter(integer()) :: 0..6
  def letter(step), do: Integer.mod(step, @steps_per_octave)
  @spec octave(integer()) :: integer()
  def octave(step), do: Integer.floor_div(step, @steps_per_octave)
  @spec step(0..6, integer()) :: integer()
  def step(letter, octave), do: octave * @steps_per_octave + letter

  @doc "MIDI number of the step with no accidental."
  @spec natural_midi(integer()) :: integer()
  def natural_midi(step) do
    @semitones_per_octave * (octave(step) + @midi_octave_offset) +
      elem(@semitones_above_c, letter(step))
  end

  @spec midi(integer(), integer()) :: integer()
  def midi(step, alter), do: natural_midi(step) + alter

  @doc "Equal-tempered frequency in Hz, A4 = 440."
  @spec frequency(number()) :: float()
  def frequency(midi), do: @a4_hz * :math.pow(2, (midi - @a4_midi) / @semitones_per_octave)

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
    case Regex.run(~r/^([A-Ga-g])(##|#|♯|x|𝄪|bb|b|♭|𝄫|♮)?(-?\d)$/u, String.trim(name)) do
      [_, letter, accidental, octave] ->
        step = step(letter_index(letter), String.to_integer(octave))
        {:ok, {step, Map.fetch!(@accidental_alters, accidental)}}

      nil ->
        {:error, :invalid_pitch}
    end
  end

  defp letter_index(letter) do
    Enum.find_index(Tuple.to_list(@letter_names), &(&1 == String.upcase(letter)))
  end

  @doc "The alteration the key signature `sf` gives `letter`: -1, 0 or 1."
  @spec key_alter(-7..7, 0..6) :: -1..1
  def key_alter(sf, letter), do: Map.get(@key_alters, {sf, letter}, 0)

  @doc "Tonic of a key as `{letter, pitch_class}`, e.g. `tonic(-1, :minor)` is D."
  @spec tonic(-7..7, :major | :minor) :: {0..6, 0..11}
  def tonic(sf, :major), do: by_fifths(sf, {0, 0})
  def tonic(sf, :minor), do: by_fifths(sf, @relative_minor)

  defp by_fifths(sf, {steps, semitones}) do
    {fifth_steps, fifth_semitones} = @fifth

    {Integer.mod(steps + fifth_steps * sf, @steps_per_octave),
     Integer.mod(semitones + fifth_semitones * sf, @semitones_per_octave)}
  end

  @doc """
  Spells a MIDI number as `{step, alter}` for key signature `sf`: the key's
  own note when there is one, otherwise a natural, otherwise sharps in sharp
  keys and flats in flat keys.
  """
  @spec spell(integer(), -7..7) :: {integer(), -2..2}
  def spell(midi, sf) do
    pitch_class = Integer.mod(midi, @semitones_per_octave)

    {letter, alter} =
      for letter <- 0..(@steps_per_octave - 1),
          alter <- @alters,
          Integer.mod(elem(@semitones_above_c, letter) + alter, @semitones_per_octave) ==
            pitch_class do
        {letter, alter}
      end
      |> Enum.min_by(&spelling_cost(&1, sf))

    octave =
      div(midi - alter - elem(@semitones_above_c, letter), @semitones_per_octave) -
        @midi_octave_offset

    {step(letter, octave), alter}
  end

  defp spelling_cost({letter, alter}, sf) do
    case key_alter(sf, letter) do
      ^alter -> 0
      _other -> @off_key_cost + @cost_per_semitone * abs(alter) + against_key(alter, sf)
    end
  end

  defp against_key(alter, sf) when alter > 0 and sf < 0, do: @against_key_cost
  defp against_key(alter, sf) when alter < 0 and sf >= 0, do: @against_key_cost
  defp against_key(_alter, _sf), do: 0
end
