defmodule DrawMusic.Music.BeamGroup do
  @moduledoc """
  Notes beamed together in one measure (see `DrawMusic.Music.Beaming`):
  the offsets of the notes or chords, in one voice of one staff.
  """

  @enforce_keys [:staff, :voice, :offsets]
  defstruct [:staff, :voice, :offsets]

  @type t :: %__MODULE__{
          staff: :treble | :bass,
          voice: pos_integer(),
          offsets: [non_neg_integer()]
        }
end
