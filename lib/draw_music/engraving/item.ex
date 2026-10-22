defmodule DrawMusic.Engraving.Item do
  @moduledoc """
  The things drawn in a system: glyphs, lines, beams, ties and the brace.
  """

  alias DrawMusic.Engraving.{Beam, Brace, Glyph, Line, Tie}

  @type t :: Glyph.t() | Line.t() | Beam.t() | Tie.t() | Brace.t()
end
