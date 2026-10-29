defmodule DrawMusic.Engraving.Staff do
  @moduledoc """
  Vertical positions on the grand staff, in staff spaces with y pointing
  down and 0 at the treble staff's top line. The bass staff hangs a fixed
  gap below the treble staff.

  Staff positions are diatonic steps (see `DrawMusic.Music.Pitch`). Every
  staff line, on both staves, falls on an even step.
  """

  alias DrawMusic.Music.Pitch

  # Five lines, four spaces apart; each space is two steps.
  @height 4
  @steps_per_space 2
  @span @height * @steps_per_space

  # Top lines: F5 on the treble staff, A3 on the bass staff.
  @top_step %{treble: 38, bass: 26}
  # The line each clef curls around: G4 for the G clef, F3 for the F clef.
  @clef_step %{treble: 32, bass: 24}
  # From the treble staff's bottom line to the bass staff's top line.
  @gap 8

  # Treble-staff key signature positions in the order the signs are written;
  # the bass staff's are two octaves lower.
  @sharps [38, 35, 39, 36, 33, 37, 34]
  @flats [34, 37, 33, 36, 32, 35, 31]
  @bass_key_shift -2 * Pitch.steps_per_octave()

  @type staff :: DrawMusic.Music.Note.staff()

  @doc "Spaces from a staff's top line to its bottom line."
  @spec height() :: pos_integer()
  def height, do: @height

  @doc "Step of the top line of `staff`."
  @spec top_step(staff()) :: integer()
  def top_step(staff), do: Map.fetch!(@top_step, staff)

  @doc "Step of the line `staff`'s clef sits on."
  @spec clef_step(staff()) :: integer()
  def clef_step(staff), do: Map.fetch!(@clef_step, staff)

  @doc "y of the top line of `staff`."
  @spec top(staff()) :: non_neg_integer()
  def top(:treble), do: 0
  def top(:bass), do: @height + @gap

  @doc "y of the bass staff's bottom line: the grand staff's height."
  @spec bottom() :: non_neg_integer()
  def bottom, do: top(:bass) + @height

  @doc "y of the middle line of `staff`."
  @spec middle(staff()) :: non_neg_integer()
  def middle(staff), do: top(staff) + div(@height, 2)

  @doc "y of `step` on `staff`."
  @spec y(staff(), integer()) :: number()
  def y(staff, step), do: top(staff) + (top_step(staff) - step) / @steps_per_space

  @doc "Whether `step` sits on a line (rather than in a space)."
  @spec line?(integer()) :: boolean()
  def line?(step), do: rem(step, @steps_per_space) == 0

  @doc "Steps of the ledger lines a note on `step` needs on `staff`."
  @spec ledger_steps(staff(), integer()) :: [integer()]
  def ledger_steps(staff, step) do
    first_above = top_step(staff) + @steps_per_space
    first_below = top_step(staff) - @span - @steps_per_space
    ledgers(step, first_above, first_below)
  end

  defp ledgers(step, above, _below) when step >= above do
    Enum.to_list(above..step//@steps_per_space)
  end

  defp ledgers(step, _above, below) when step <= below do
    Enum.to_list(below..step//-@steps_per_space)
  end

  defp ledgers(_step, _above, _below), do: []

  @doc "Steps of the key signature's signs on `staff`, in writing order."
  @spec key_signature_steps(staff(), -7..7) :: [integer()]
  def key_signature_steps(staff, sf) do
    sf
    |> sign_order()
    |> Enum.take(abs(sf))
    |> Enum.map(&(&1 + key_shift(staff)))
  end

  defp sign_order(sf) when sf >= 0, do: @sharps
  defp sign_order(_sf), do: @flats

  defp key_shift(:treble), do: 0
  defp key_shift(:bass), do: @bass_key_shift
end
