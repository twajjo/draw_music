defmodule DrawMusicWeb.EditorGeometry.Payload do
  @moduledoc """
  The score geometry the `ScoreEditor` browser hook maps the pointer with
  (sent as JSON in `data-geometry`): each system's place and measures, the
  staves' positions and the key. Units are staff spaces.
  """

  alias DrawMusicWeb.EditorGeometry.{StaffPositions, SystemPayload}

  @derive Jason.Encoder
  @enforce_keys [:systems, :staff_top, :top_step, :padding, :sf, :ppq]
  defstruct [:systems, :staff_top, :top_step, :padding, :sf, :ppq]

  @type t :: %__MODULE__{
          systems: [SystemPayload.t()],
          staff_top: StaffPositions.t(),
          top_step: StaffPositions.t(),
          padding: number(),
          sf: -7..7,
          ppq: pos_integer()
        }
end
