defmodule DrawMusic.Engraving.MeasureGeometry do
  @moduledoc """
  Where a measure sits in its system, and how its ticks map to x: tick `t`
  lies at `content_x + (t - start_tick) * scale` (see
  `DrawMusic.Engraving.Layout.x_of/2`). Sent to the editor's browser hook
  as JSON.
  """

  @derive Jason.Encoder
  @enforce_keys [:index, :x, :width, :start_tick, :capacity, :content_x, :scale]
  defstruct [:index, :x, :width, :start_tick, :capacity, :content_x, :scale]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          x: float(),
          width: float(),
          start_tick: non_neg_integer(),
          capacity: pos_integer(),
          content_x: float(),
          scale: float()
        }
end
