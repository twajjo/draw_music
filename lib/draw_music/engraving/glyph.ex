defmodule DrawMusic.Engraving.Glyph do
  @moduledoc """
  A SMuFL glyph at (x, y), its origin on the baseline. `role` says what it
  is; noteheads and rests carry their event's `id` (nil for the implied
  whole-bar rest of an empty staff).
  """

  @enforce_keys [:role, :glyph, :x, :y]
  defstruct [:role, :glyph, :x, :y, :id]

  @type role :: :clef | :key | :time | :notehead | :accidental | :dot | :flag | :rest

  @type t :: %__MODULE__{
          role: role(),
          glyph: atom(),
          x: number(),
          y: number(),
          id: Ecto.UUID.t() | nil
        }
end
