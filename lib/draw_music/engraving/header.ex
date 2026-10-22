defmodule DrawMusic.Engraving.Header do
  @moduledoc """
  The start of a system: brace, clefs, key signature and (on the first
  system) time signature. `line_x` is where the staff lines begin; `width`
  where the first measure does.
  """

  alias DrawMusic.Engraving.Item

  @enforce_keys [:items, :line_x, :width]
  defstruct [:items, :line_x, :width]

  @type t :: %__MODULE__{items: [Item.t()], line_x: float(), width: float()}
end
