defmodule DrawMusic.Engraving.Line do
  @moduledoc """
  A straight line: a staff line, ledger line, stem (with its direction) or
  bar line.
  """

  @enforce_keys [:role, :x1, :y1, :x2, :y2, :thickness]
  defstruct [:role, :x1, :y1, :x2, :y2, :thickness, :dir]

  @type t :: %__MODULE__{
          role: :staff | :ledger | :stem | :barline,
          x1: number(),
          y1: number(),
          x2: number(),
          y2: number(),
          thickness: float(),
          dir: :up | :down | nil
        }
end
