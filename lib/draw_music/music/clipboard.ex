defmodule DrawMusic.Music.Clipboard do
  @moduledoc """
  Copied notes and rests (see `DrawMusic.Music.Editing.copy/3`): entries
  timed from the earliest one, so a paste can put them anywhere.
  """

  alias DrawMusic.Music.Entry

  defstruct entries: []

  @type t :: %__MODULE__{entries: [Entry.t()]}
end
