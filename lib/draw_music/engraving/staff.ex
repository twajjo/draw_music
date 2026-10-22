defmodule DrawMusic.Engraving.Staff do
  @moduledoc """
  Vertical positions on the grand staff, in staff spaces with y pointing
  down and 0 at the treble staff's top line. The bass staff hangs a fixed
  gap below the treble staff.

  Staff positions are diatonic steps (see `DrawMusic.Music.Pitch`). Every
  staff line, on both staves, falls on an even step.
  """

  # Top lines: F5 on the treble staff, A3 on the bass staff.
  @top_step %{treble: 38, bass: 26}
  # From the treble staff's bottom line to the bass staff's top line.
  @gap 8

  # Key signature positions in the order the signs are written.
  @sharps [38, 35, 39, 36, 33, 37, 34]
  @flats [34, 37, 33, 36, 32, 35, 31]

  @doc "y of the top line of `staff`."
  def top(:treble), do: 0
  def top(:bass), do: 4 + @gap

  @doc "y of the bass staff's bottom line: the grand staff's height."
  def bottom, do: top(:bass) + 4

  @doc "y of the middle line of `staff`."
  def middle(staff), do: top(staff) + 2

  @doc "y of `step` on `staff`."
  def y(staff, step), do: top(staff) + (Map.fetch!(@top_step, staff) - step) / 2

  @doc "Whether `step` sits on a line (rather than in a space)."
  def line?(step), do: rem(step, 2) == 0

  @doc "Steps of the ledger lines a note on `step` needs on `staff`."
  def ledger_steps(staff, step) do
    top = Map.fetch!(@top_step, staff)
    bottom = top - 8

    cond do
      step >= top + 2 -> Enum.to_list((top + 2)..step//2)
      step <= bottom - 2 -> Enum.to_list((bottom - 2)..step//-2)
      true -> []
    end
  end

  @doc "Steps of the key signature's signs on `staff`, in writing order."
  def key_signature_steps(staff, sf) do
    shift = if staff == :bass, do: -14, else: 0
    steps = if sf >= 0, do: @sharps, else: @flats
    steps |> Enum.take(abs(sf)) |> Enum.map(&(&1 + shift))
  end
end
