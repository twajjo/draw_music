defmodule DrawMusic.Music.KeyFit do
  @moduledoc """
  How well one key suits a score's notes: its key signature `sf` and `mode`,
  its `fit` (`DrawMusic.Music.KeyDetection.ranked/1`'s correlation, higher is
  better) and the `accidentals` the score would be written with in it.
  """

  @enforce_keys [:sf, :mode, :fit, :accidentals]
  defstruct [:sf, :mode, :fit, :accidentals]

  @type t :: %__MODULE__{
          sf: -7..7,
          mode: :major | :minor,
          fit: float(),
          accidentals: non_neg_integer()
        }
end
