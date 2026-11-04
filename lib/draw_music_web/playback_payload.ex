defmodule DrawMusicWeb.PlaybackPayload do
  @moduledoc """
  What the editor sends the browser hook to play (the `play` event): the
  sounds, timed from where playback starts, how long the span lasts in
  seconds (rests included, so a loop repeats in time), and whether to loop.
  `anchors` (ticks on the score and when playback reaches them, through
  any tempo changes) let the hook place the playhead. An audition sends
  none.
  """

  alias DrawMusic.Music.{PlaybackAnchor, PlaybackEvent}

  @derive Jason.Encoder
  @enforce_keys [:events, :span, :loop]
  defstruct [:events, :span, :loop, anchors: []]

  @type t :: %__MODULE__{
          events: [PlaybackEvent.t()],
          span: float(),
          loop: boolean(),
          anchors: [PlaybackAnchor.t()]
        }
end
