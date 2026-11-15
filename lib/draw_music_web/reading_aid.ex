defmodule DrawMusicWeb.ReadingAid do
  @moduledoc """
  A reading aid's label drawn on the editor's score: a tiny letter at `x`,
  `y` (staff spaces, in its system's coordinates). `kind` says what it names:
  a staff `:line` or `:space`, or `:middle_c`.

  Only the editor draws these (see `DrawMusicWeb.ReadingAids`); they are never
  part of the engraving, so exported sheet music never has them.
  """

  @enforce_keys [:x, :y, :text, :kind]
  defstruct [:x, :y, :text, :kind]

  @type t :: %__MODULE__{
          x: float(),
          y: float(),
          text: String.t(),
          kind: :line | :space | :middle_c
        }
end
