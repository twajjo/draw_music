defmodule DrawMusicWeb.PlaybackPayload do
  @moduledoc """
  What the editor sends the browser hook to play (the `play` event): the
  sounds, timed from where playback starts.
  """

  alias DrawMusic.Music.PlaybackEvent

  @derive Jason.Encoder
  @enforce_keys [:events]
  defstruct [:events]

  @type t :: %__MODULE__{events: [PlaybackEvent.t()]}
end
