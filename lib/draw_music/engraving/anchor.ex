defmodule DrawMusic.Engraving.Anchor do
  @moduledoc """
  Where a notehead was drawn, for attaching ties: its left and right edges,
  its y, its stem direction and (once known) its system.
  """

  @enforce_keys [:x0, :x1, :y, :dir]
  defstruct [:x0, :x1, :y, :dir, :system]

  @type t :: %__MODULE__{
          x0: float(),
          x1: float(),
          y: float(),
          dir: :up | :down,
          system: non_neg_integer() | nil
        }
end
