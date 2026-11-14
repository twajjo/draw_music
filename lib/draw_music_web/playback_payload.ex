defmodule DrawMusicWeb.PlaybackPayload do
  @moduledoc """
  What the editor sends the browser hook to play (the `play` event): the
  sounds, timed from the start of the span, how long the span lasts in
  seconds (rests included, so a loop repeats in time), whether to loop, and
  `at`, how many seconds into the span to start (a loop still goes round
  the whole span). `anchors` (ticks on the score and when playback reaches
  them, through any tempo changes) let the hook place the playhead. An
  audition sends none.
  """

  alias DrawMusic.Music.{PlaybackAnchor, PlaybackEvent}

  @derive Jason.Encoder
  @enforce_keys [:events, :span, :loop]
  defstruct [:events, :span, :loop, anchors: [], at: 0.0]

  @type t :: %__MODULE__{
          events: [PlaybackEvent.t()],
          span: float(),
          loop: boolean(),
          anchors: [PlaybackAnchor.t()],
          at: float()
        }
end
