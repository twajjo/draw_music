defmodule DrawMusicWeb.EditorGeometry.SystemPayload do
  @moduledoc "One system as the browser hook needs it: where it sits and its measures."

  alias DrawMusic.Engraving.MeasureGeometry

  @derive Jason.Encoder
  @enforce_keys [:y, :width, :measures]
  defstruct [:y, :width, :measures]

  @type t :: %__MODULE__{y: float(), width: float(), measures: [MeasureGeometry.t()]}
end
