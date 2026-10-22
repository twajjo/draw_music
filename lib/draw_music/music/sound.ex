defmodule DrawMusic.Music.Sound do
  @moduledoc """
  One sounding note: a note, or a tied chain of notes sounding once for
  their total length (see `DrawMusic.Music.Playback.sounds/2`).
  """

  @enforce_keys [:ids, :staff, :midi, :start, :ticks]
  defstruct [:ids, :staff, :midi, :start, :ticks]

  @type t :: %__MODULE__{
          ids: [Ecto.UUID.t()],
          staff: :treble | :bass,
          midi: 21..108,
          start: non_neg_integer(),
          ticks: pos_integer()
        }
end
