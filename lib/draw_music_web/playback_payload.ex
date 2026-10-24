defmodule DrawMusicWeb.PlaybackPayload do
  @moduledoc """
  What the editor sends the browser hook to play (the `play` event): the
  sounds, timed from where playback starts, and whether to loop them.
  """

  alias DrawMusic.Music.PlaybackEvent

  @derive Jason.Encoder
  @enforce_keys [:events, :loop]
  defstruct [:events, :loop]

  @type t :: %__MODULE__{events: [PlaybackEvent.t()], loop: boolean()}
end
