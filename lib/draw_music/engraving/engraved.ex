defmodule DrawMusic.Engraving.Engraved do
  @moduledoc """
  An engraved score (from `DrawMusic.Engraving.Layout.layout/3`): its
  systems stacked down the page, with the page's size. Units are staff
  spaces, y pointing down.
  """

  alias DrawMusic.Engraving.System

  @enforce_keys [:width, :height, :systems]
  defstruct [:width, :height, :systems]

  @type t :: %__MODULE__{width: float(), height: float(), systems: [System.t()]}
end
