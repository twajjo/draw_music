defmodule DrawMusic.Music.PlaybackEvent do
  @moduledoc """
  A sound scheduled for playback, timed in seconds from where playback
  starts (see `DrawMusic.Music.Playback.events/3`). Sent to the browser as
  JSON; `ids` are the notes to light up while it sounds.
  """

  @derive Jason.Encoder
  @enforce_keys [:ids, :midi, :frequency, :tick, :start, :duration]
  defstruct [:ids, :midi, :frequency, :tick, :start, :duration]

  @type t :: %__MODULE__{
          ids: [Ecto.UUID.t()],
          midi: 21..108,
          frequency: float(),
          tick: non_neg_integer(),
          start: float(),
          duration: float()
        }
end
