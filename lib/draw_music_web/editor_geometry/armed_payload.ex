defmodule DrawMusicWeb.EditorGeometry.ArmedPayload do
  @moduledoc """
  The armed palette item as the browser hook needs it (sent as JSON in
  `data-armed`): what it is, the glyph to draw as the cursor (nil for the
  tie tool), the time grid of its placement zones
  (`DrawMusic.Music.Context.zone_ticks/2`), its own length in ticks (dots
  included: what it will cover), and for a chord its shape, to preview it
  whole.
  """

  alias DrawMusicWeb.EditorGeometry.ChordShape

  @derive Jason.Encoder
  @enforce_keys [:kind, :value, :dots, :grid, :ticks]
  defstruct [:kind, :value, :dots, :alter, :glyph, :grid, :ticks, :chord]

  @type t :: %__MODULE__{
          kind: :note | :rest | :chord | :tie,
          value: atom(),
          dots: 0..2,
          alter: -2..2 | nil,
          glyph: String.t() | nil,
          grid: pos_integer(),
          ticks: pos_integer(),
          chord: ChordShape.t() | nil
        }
end
