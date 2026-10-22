defmodule DrawMusicWeb.BarControl do
  @moduledoc """
  Where a bar's ⊕/⊖ controls sit over the score, in percent of the score's
  box (so they follow both layouts): its top-left corner, and its right
  edge (for the add-bar button after the last bar).
  """

  @enforce_keys [:index, :left, :top, :end_left]
  defstruct [:index, :left, :top, :end_left]

  @type t :: %__MODULE__{index: non_neg_integer(), left: float(), top: float(), end_left: float()}
end
