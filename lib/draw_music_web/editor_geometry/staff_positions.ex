defmodule DrawMusicWeb.EditorGeometry.StaffPositions do
  @moduledoc "A value for each staff of the grand staff (e.g. its top line's y or step)."

  @derive Jason.Encoder
  @enforce_keys [:treble, :bass]
  defstruct [:treble, :bass]

  @type t :: %__MODULE__{treble: number(), bass: number()}
end
