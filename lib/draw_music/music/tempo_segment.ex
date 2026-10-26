defmodule DrawMusic.Music.TempoSegment do
  @moduledoc """
  A stretch of a score's timeline (see `DrawMusic.Music.TempoMap`) whose
  tempo is steady (`from_bpm == to_bpm`) or moves evenly from `from_bpm` at
  `start` to `to_bpm` at `stop`. The last stretch never stops.
  """

  @enforce_keys [:start, :stop, :from_bpm, :to_bpm]
  defstruct [:start, :stop, :from_bpm, :to_bpm]

  @type t :: %__MODULE__{
          start: non_neg_integer(),
          stop: non_neg_integer() | :infinity,
          from_bpm: number(),
          to_bpm: number()
        }
end
