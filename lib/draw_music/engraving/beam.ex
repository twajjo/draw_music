defmodule DrawMusic.Engraving.Beam do
  @moduledoc """
  A beam whose edge runs from (x1, y1) to (x2, y2), extending by
  `thickness` (positive is downwards).
  """

  @enforce_keys [:x1, :y1, :x2, :y2, :thickness]
  defstruct [:x1, :y1, :x2, :y2, :thickness]

  @type t :: %__MODULE__{x1: float(), y1: float(), x2: float(), y2: float(), thickness: float()}
end
