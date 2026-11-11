defmodule DrawMusicWeb.Editor.Intent do
  @moduledoc """
  How the editor's components tell `DrawMusicWeb.EditorLive` about an
  overall result. A component calls `notify/1`, which sends
  `{:editor, intent}` to the LiveView it runs in. The editor handles each
  intent once, in one `handle_info` clause.

  ## Intents
    * `{:open, dialog}`: open this dialog over the score (one of the
      `@dialog` values, e.g. `:save_as`).
    * `:close`: close the open dialog.
    * `{:saved, version, message}`: the score was stored as `version`,
      which has its key and composition loaded. If it is the version being
      edited, the editor carries on with it. Otherwise the editor opens it.
      `message` tells the user.
    * `{:flash, kind, message}`: show a flash (`:info` or `:error`). A
      component's own flash wouldn't reach the page's layout.
  """

  alias DrawMusic.Library.Version

  @type t ::
          {:open, atom()}
          | :close
          | {:saved, Version.t(), String.t()}
          | {:flash, :info | :error, String.t()}

  @doc "Sends `intent` to the editor (the LiveView this process runs)."
  @spec notify(t()) :: {:editor, t()}
  def notify(intent), do: send(self(), {:editor, intent})
end
