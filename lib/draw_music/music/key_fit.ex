defmodule DrawMusic.Music.KeyFit do
  @moduledoc """
  How well one key suits a score's notes: its key signature `sf` and `mode`,
  its `fit` (`DrawMusic.Music.KeyDetection.ranked/1`'s correlation, higher is
  better), the `accidentals` the score would be written with in it, and the
  different notes those are (`accidental_notes`, e.g. `["F♯", "B♮"]`, in the
  order they first come).
  """

  @enforce_keys [:sf, :mode, :fit, :accidentals, :accidental_notes]
  defstruct [:sf, :mode, :fit, :accidentals, :accidental_notes]

  @type t :: %__MODULE__{
          sf: -7..7,
          mode: :major | :minor,
          fit: float(),
          accidentals: non_neg_integer(),
          accidental_notes: [String.t()]
        }
end
