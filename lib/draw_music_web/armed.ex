defmodule DrawMusicWeb.Armed do
  @moduledoc """
  The palette item ready to be placed (see `DrawMusicWeb.EditorPalette`).
  `alter` is nil (follow the key) or -2..2; `chord` is set for chords. It stays
  armed after placing, until another item is picked or it is disarmed.
  """

  alias DrawMusic.Music.{Chords, Duration}

  @enforce_keys [:kind, :value]
  defstruct [:kind, :value, :alter, :chord, dots: 0]

  @type chord :: {:quality, Chords.quality()} | {:degree, 1..7}

  @type t :: %__MODULE__{
          kind: :note | :rest | :chord | :tie,
          value: Duration.value(),
          dots: 0..2,
          alter: -2..2 | nil,
          chord: chord() | nil
        }
end
