defmodule DrawMusic.Engraving.System do
  @moduledoc """
  One line of music: a grand staff carrying some measures. `y` is where its
  treble staff's top line sits on the page; its items are positioned
  relative to that line. `top` and `bottom` bound its band of the page:
  everything it draws, and the gap below it. The bands tile the page.
  """

  alias DrawMusic.Engraving.{Item, MeasureGeometry}

  @enforce_keys [:index, :width, :measures, :items]
  defstruct [:index, :width, :measures, :items, y: 0.0, top: 0.0, bottom: 0.0]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          y: float(),
          top: float(),
          bottom: float(),
          width: float(),
          measures: [MeasureGeometry.t()],
          items: [Item.t()]
        }
end
