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

  @doc """
  Which chord an entry belongs to: its staff, voice and start. Notes with
  the same key sound together as one chord (a voice's notes that start
  together have the same length, or the edit was refused).
  """
  @spec chord_key(t()) :: {Note.staff(), Note.voice(), non_neg_integer()}
  def chord_key(%__MODULE__{event: event, start: start}), do: {event.staff, event.voice, start}
end
