defmodule DrawMusic.Engraving.ChordLayout do
  @moduledoc """
  A chord (or single note) as laid out by `DrawMusic.Engraving.Notes`: its
  stem direction, notehead glyph and column, vertical extent, the items
  drawn for it, and the tie anchors of its notes.
  """

  alias DrawMusic.Engraving.{Anchor, Item}
  alias DrawMusic.Music.Duration

  @enforce_keys [:staff, :dir, :value, :glyph, :x, :top_y, :bottom_y, :items, :anchors]
  defstruct [:staff, :dir, :value, :glyph, :x, :top_y, :bottom_y, :items, :anchors]

  @type t :: %__MODULE__{
          staff: :treble | :bass,
          dir: :up | :down,
          value: Duration.value(),
          glyph: atom(),
          x: float(),
          top_y: float(),
          bottom_y: float(),
          items: [Item.t()],
          anchors: [{Ecto.UUID.t(), Anchor.t()}]
        }
end
