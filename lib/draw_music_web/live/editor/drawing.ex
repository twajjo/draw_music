defmodule DrawMusicWeb.Editor.Drawing do
  @moduledoc """
  The score as `DrawMusicWeb.EditorLive` last laid it out, rebuilt together
  after each change:

    * `engraved`: the `DrawMusic.Engraving.Engraved` layout;
    * `pieces`: it drawn, with the user's reading aids
      (`DrawMusicWeb.ScoreSvg.pieces/2`);
    * `geometry_json`: where things are, for the score's hook
      (`DrawMusicWeb.EditorGeometry.encode/2`, as JSON);
    * `loading?`: whether it is still the placeholder shown until the score
      is engraved;
    * `key_suggestion`: better keys for the score
      (`DrawMusic.Music.KeySuggestion`), for the Suggest key button.
  """

  alias DrawMusic.Engraving.Engraved
  alias DrawMusic.Music.KeySuggestion

  @enforce_keys [:engraved, :pieces, :geometry_json, :loading?, :key_suggestion]
  defstruct [:engraved, :pieces, :geometry_json, :loading?, :key_suggestion]

  @type t :: %__MODULE__{
          engraved: Engraved.t(),
          pieces: list(),
          geometry_json: String.t(),
          loading?: boolean(),
          key_suggestion: KeySuggestion.t()
        }
end
