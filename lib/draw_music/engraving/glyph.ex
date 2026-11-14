defmodule DrawMusic.Engraving.Glyph do
  @moduledoc """
  A SMuFL glyph at (x, y), its origin on the baseline. `role` says what it
  is; noteheads and rests carry their event's `id` (nil for implied rests,
  which fill gaps but aren't stored). Noteheads also carry their `staff`
  and their note's `alter` (for the editor's drag preview).
  """

  @enforce_keys [:role, :glyph, :x, :y]
  defstruct [:role, :glyph, :x, :y, :id, :staff, :alter]

  @type role :: :clef | :key | :time | :notehead | :accidental | :dot | :flag | :rest

  @type t :: %__MODULE__{
          role: role(),
          glyph: atom(),
          x: number(),
          y: number(),
          id: Ecto.UUID.t() | nil,
          staff: :treble | :bass | nil,
          alter: -2..2 | nil
        }
end
