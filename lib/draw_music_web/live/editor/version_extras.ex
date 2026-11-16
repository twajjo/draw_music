defmodule DrawMusicWeb.Editor.VersionExtras do
  @moduledoc """
  What a version saves beside its score, outside the score's
  `DrawMusic.Music.Context`: the opening tempo marking's words and the
  playback instrument (a General MIDI program). Changing either is unsaved
  work, like an edit.
  """

  alias DrawMusic.Library.Version

  @enforce_keys [:tempo_text, :instrument]
  defstruct [:tempo_text, :instrument]

  @type t :: %__MODULE__{tempo_text: String.t() | nil, instrument: 0..127 | nil}

  @doc "The extras `version` was saved with."
  @spec from_version(Version.t()) :: t()
  def from_version(%Version{tempo_text: tempo_text, instrument: instrument}) do
    %__MODULE__{tempo_text: tempo_text, instrument: instrument}
  end
end
