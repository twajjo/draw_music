defmodule DrawMusicWeb.PlaybackPayload do
  @moduledoc """
  What the editor sends the browser hook to play (the `play` event): the
  sounds, timed from where playback starts, how long the span lasts in
  seconds (rests included, so a loop repeats in time), and whether to loop.
  """

  alias DrawMusic.Music.PlaybackEvent

  @derive Jason.Encoder
  @enforce_keys [:events, :span, :loop]
  defstruct [:events, :span, :loop]

  @type t :: %__MODULE__{events: [PlaybackEvent.t()], span: float(), loop: boolean()}
end
