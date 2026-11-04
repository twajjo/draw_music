defmodule DrawMusic.Music.Placement do
  @moduledoc """
  What to place and where in a measure, for `DrawMusic.Music.Editing`'s
  `place_note/4`, `place_rest/4` and `place_chord/5`. `offset` is ticks into
  the measure; `step` and `alter` give a note's pitch (unused for rests and
  chords); a nil `voice` means the lowest voice it fits in. With
  `cross_bar`, an item running past the bar line is split there into tied
  notes (or rests) instead of being refused. With `overwrite` (Overlay
  mode), the item replaces the time it covers on its staff, in every voice.
  """

  alias DrawMusic.Music.Duration

  @enforce_keys [:staff, :offset, :value]
  defstruct [
    :staff,
    :offset,
    :value,
    :step,
    :voice,
    dots: 0,
    alter: 0,
    cross_bar: false,
    overwrite: false
  ]

  @type t :: %__MODULE__{
          staff: :treble | :bass,
          offset: non_neg_integer(),
          value: Duration.value(),
          dots: 0..2,
          step: integer() | nil,
          alter: -2..2,
          voice: DrawMusic.Music.Note.voice() | nil,
          cross_bar: boolean(),
          overwrite: boolean()
        }
end
