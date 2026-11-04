defmodule DrawMusicWeb.InstrumentSource do
  @moduledoc """
  Where the editor's browser hook loads a program's sound from (the
  `data-instrument` attribute): the Splendid Grand Piano set, a MusyngKite
  soundfont, or nothing installed, in which case it plays its built-in
  synth.
  """

  alias DrawMusic.Samples

  @samples_path "/samples"

  @derive Jason.Encoder
  @enforce_keys [:program, :name, :kind, :url]
  defstruct [:program, :name, :kind, :url]

  @type t :: %__MODULE__{
          program: 0..127,
          name: String.t(),
          kind: :splendid | :soundfont | :synth,
          url: String.t() | nil
        }

  @doc "The source for a GM program, from what is installed now."
  @spec for_program(0..127) :: t()
  def for_program(program) do
    instrument = Samples.instrument!(program)
    {kind, url} = source(instrument, Samples.splendid?(), Samples.installed?(program))
    %__MODULE__{program: program, name: instrument.name, kind: kind, url: url}
  end

  defp source(%{program: 0}, true = _splendid?, _installed?) do
    {:splendid, "#{@samples_path}/#{Samples.relative_path(:splendid)}"}
  end

  defp source(instrument, _splendid?, true = _installed?) do
    {:soundfont, "#{@samples_path}/#{Samples.relative_path(instrument)}"}
  end

  defp source(_instrument, _splendid?, false = _installed?), do: {:synth, nil}
end
