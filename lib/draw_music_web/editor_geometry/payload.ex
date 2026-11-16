defmodule DrawMusicWeb.EditorGeometry.Payload do
  @moduledoc """
  The score geometry the `.ScoreCanvas` browser hook maps the pointer with
  (sent as JSON in `data-geometry`): each system's place and measures, the
  staves' positions, the key, and the width of a bar rest (to hit-test it
  where it's drawn, centred in its bar). Units are staff spaces.
  """

  alias DrawMusicWeb.EditorGeometry.{StaffPositions, SystemPayload}

  @derive Jason.Encoder
  @enforce_keys [:systems, :staff_top, :top_step, :padding, :sf, :ppq, :bar_rest_width]
  defstruct [:systems, :staff_top, :top_step, :padding, :sf, :ppq, :bar_rest_width]

  @type t :: %__MODULE__{
          systems: [SystemPayload.t()],
          staff_top: StaffPositions.t(),
          top_step: StaffPositions.t(),
          padding: number(),
          sf: -7..7,
          ppq: pos_integer(),
          bar_rest_width: float()
        }
end
