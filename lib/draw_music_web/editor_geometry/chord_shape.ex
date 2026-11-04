defmodule DrawMusicWeb.EditorGeometry.ChordShape do
  @moduledoc """
  An armed chord as the browser hook needs it to preview the chord while
  placing (part of `DrawMusicWeb.EditorGeometry.ArmedPayload`):

    * `:quality` — `tones` are `[letter steps, semitones]` above whatever
      root the pointer is on;
    * `:degree` — the key's chord on `root_letter` (0 = C … 6 = B), whose
      octave the pointer picks; `tones` are `[letter steps, alteration]`.

  `suffix` and `numeral` name it (`"m"`, `"ii"`).
  """

  @derive Jason.Encoder
  @enforce_keys [:kind, :tones, :suffix]
  defstruct [:kind, :tones, :suffix, :root_letter, :numeral]

  @type t :: %__MODULE__{
          kind: :quality | :degree,
          tones: [[integer()]],
          suffix: String.t(),
          root_letter: 0..6 | nil,
          numeral: String.t() | nil
        }
end
