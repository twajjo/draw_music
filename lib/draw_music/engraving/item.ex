defmodule DrawMusic.Engraving.Item do
  @moduledoc """
  The things drawn in a system: glyphs, lines, beams, ties, the brace and
  tempo marks.
  """

  alias DrawMusic.Engraving.{Beam, Brace, Glyph, Line, TempoMark, Tie}

  @type t :: Glyph.t() | Line.t() | Beam.t() | Tie.t() | Brace.t() | TempoMark.t()
end
