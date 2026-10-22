defmodule DrawMusicWeb.PlacementTarget do
  @moduledoc """
  Where the user clicked to place, as validated from the browser's `place`
  event (see `DrawMusicWeb.EditorPlacement.parse/1`): measure, offset into
  it, staff and step, and the alteration of a held modifier (nil if none).
  """

  @enforce_keys [:measure, :offset, :staff, :step]
  defstruct [:measure, :offset, :staff, :step, :alter]

  @type t :: %__MODULE__{
          measure: non_neg_integer(),
          offset: non_neg_integer(),
          staff: :treble | :bass,
          step: integer(),
          alter: -2..2 | nil
        }
end
