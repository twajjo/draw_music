defmodule DrawMusic.Engraving.Brace do
  @moduledoc "The brace joining a grand staff, from y1 to y2 at x."

  @enforce_keys [:x, :y1, :y2]
  defstruct [:x, :y1, :y2]

  @type t :: %__MODULE__{x: number(), y1: number(), y2: number()}
end
