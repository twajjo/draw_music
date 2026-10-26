defmodule DrawMusic.Music.PlaybackAnchor do
  @moduledoc """
  A point the playhead passes: `tick` on the score, `seconds` after
  playback starts (see `DrawMusic.Music.TempoMap.anchors/3`). Sent to the
  browser as JSON.
  """

  @derive Jason.Encoder
  @enforce_keys [:seconds, :tick]
  defstruct [:seconds, :tick]

  @type t :: %__MODULE__{seconds: float(), tick: non_neg_integer()}
end
