defmodule DrawMusic.Engraving.Column do
  @moduledoc """
  One moment of a measure where something starts on either staff: its
  `offset` (ticks into the measure), the `x` its noteheads and rests are
  drawn at, and the `staves` that have something starting there. Columns
  are shared by the grand staff, so both staves stay aligned; each has an
  insertion gap to its left (see `DrawMusic.Engraving.MeasureGeometry`).
  """

  @derive Jason.Encoder
  @enforce_keys [:offset, :x, :staves]
  defstruct [:offset, :x, :staves]

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          x: float(),
          staves: [:treble | :bass]
        }
end
