defmodule DrawMusic.Library.Import do
  @moduledoc """
  A piece read from a file (see `DrawMusic.MidiCodec.import/2`), ready for
  `DrawMusic.Library.import_score/4`: its name and the changeset attrs for
  its composition, key and version.
  """

  # Embedded in exported MIDI files (see `DrawMusic.MidiCodec`); the name
  # travels as the file's track name instead.
  @derive {JSON.Encoder, only: [:composition, :key, :version]}
  @enforce_keys [:name, :key, :version]
  defstruct [:name, :key, :version, composition: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          composition: map(),
          key: map(),
          version: map()
        }
end
