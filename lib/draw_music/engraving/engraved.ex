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

  @doc "Where each line of music (system) starts, in ticks, in order."
  @spec line_starts(t()) :: [non_neg_integer()]
  def line_starts(%__MODULE__{systems: systems}) do
    for system <- systems, do: hd(system.measures).start_tick
  end

  @doc "Where each measure starts, in ticks, in order."
  @spec measure_starts(t()) :: [non_neg_integer()]
  def measure_starts(%__MODULE__{systems: systems}) do
    for system <- systems, measure <- system.measures, do: measure.start_tick
  end
end
