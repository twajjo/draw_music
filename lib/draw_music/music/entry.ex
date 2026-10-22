defmodule DrawMusic.Music.Entry do
  @moduledoc """
  A note or rest placed on the score's absolute time axis: `start` and
  `ticks` count from the beginning of the piece (see
  `DrawMusic.Music.Timeline`). Edits work on entries, then re-bar them.
  """

  alias DrawMusic.Music.{Note, Rest}

  @enforce_keys [:kind, :start, :ticks, :event]
  defstruct [:kind, :start, :ticks, :event]

  @type t :: %__MODULE__{
          kind: :note | :rest,
          start: non_neg_integer(),
          ticks: pos_integer(),
          event: Note.t() | Rest.t()
        }
end
