defmodule DrawMusic.Engraving.TempoMark do
  @moduledoc """
  A tempo change drawn above a system (see `DrawMusic.Music.TempoChange`),
  its baseline at `y`. A steady change is a label, "♩ = 90", at `x`.

  A rit. or accel. is the label with its word ("♩ = 60 rit."), then a
  dashed line to `line_to`, where "♩ = 45" gives the tempo it reaches. One
  crossing system breaks is drawn in pieces, one per system: only the
  first has the label (`start?`), only the last the end tempo (`end?`).
  `width` is how much room the label takes, so marks don't overlap.
  """

  @enforce_keys [:id, :x, :y, :bpm, :width]
  defstruct [:id, :x, :y, :bpm, :width, :to_bpm, :ramp, :line_to, start?: true, end?: false]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          x: number(),
          y: number(),
          bpm: pos_integer(),
          width: number(),
          to_bpm: pos_integer() | nil,
          ramp: :rit | :accel | nil,
          line_to: number() | nil,
          start?: boolean(),
          end?: boolean()
        }

  # Rough text widths, in staff spaces, at the size marks are drawn.
  @char_width 0.95
  @note_width 1.3

  @doc ~s(The words a mark's label shows after its note: "= 90", "= 60 rit.".)
  @spec label(t()) :: String.t()
  def label(%__MODULE__{bpm: bpm, ramp: nil}), do: "= #{bpm}"
  def label(%__MODULE__{bpm: bpm, ramp: :rit}), do: "= #{bpm} rit."
  def label(%__MODULE__{bpm: bpm, ramp: :accel}), do: "= #{bpm} accel."

  @doc ~s(The end tempo's words: "= 45".)
  @spec end_label(t()) :: String.t()
  def end_label(%__MODULE__{to_bpm: to_bpm}), do: "= #{to_bpm}"

  @doc "How wide a note and `text` are, roughly."
  @spec text_width(String.t()) :: float()
  def text_width(text), do: @note_width + @char_width * String.length(text)
end
