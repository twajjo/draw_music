defmodule DrawMusicWeb.EditorGeometry.ArmedPayload do
  @moduledoc """
  The armed palette item as the browser hook needs it (sent as JSON in
  `data-armed`): what it is, the glyph to draw as the cursor (nil for the
  tie tool) and the time grid to snap to (the undotted value's length).
  """

  @derive Jason.Encoder
  @enforce_keys [:kind, :value, :dots, :locked, :grid]
  defstruct [:kind, :value, :dots, :alter, :locked, :glyph, :grid]

  @type t :: %__MODULE__{
          kind: :note | :rest | :chord | :tie,
          value: atom(),
          dots: 0..2,
          alter: -2..2 | nil,
          locked: boolean(),
          glyph: String.t() | nil,
          grid: pos_integer()
        }
end
