defmodule DrawMusic.Samples.Instrument do
  @moduledoc """
  A General MIDI instrument: its program number, display name, GM family
  and the file stem of its MusyngKite soundfont (`flute` for
  `flute-mp3.js`).
  """

  @enforce_keys [:program, :name, :family, :stem]
  defstruct [:program, :name, :family, :stem]

  @type t :: %__MODULE__{
          program: 0..127,
          name: String.t(),
          family: String.t(),
          stem: String.t()
        }
end
