defmodule DrawMusic.Engraving.Head do
  @moduledoc """
  A notehead of a chord as laid out: its note, position, and whether it was
  moved across the stem (a second from its neighbour).
  """

  alias DrawMusic.Music.Note

  @enforce_keys [:note, :x, :y, :moved]
  defstruct [:note, :x, :y, :moved]

  @type t :: %__MODULE__{note: Note.t(), x: float(), y: float(), moved: boolean()}
end
