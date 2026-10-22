defmodule DrawMusic.Engraving.Tie do
  @moduledoc "A tie: an arc from x1 to x2 at height y, bulging `dir`."

  @enforce_keys [:x1, :x2, :y, :dir]
  defstruct [:x1, :x2, :y, :dir]

  @type t :: %__MODULE__{x1: float(), x2: float(), y: float(), dir: :up | :down}
end
