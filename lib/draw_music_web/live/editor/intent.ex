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
    * `{:edit, fun}`: apply an edit to the score, undoably. `fun` is a
      `DrawMusic.Music.Session.edit/2` function, `(score, ctx -> result)`.
    * `{:edit, fun, :select}`: the same, and select what it reports
      (`{:ok, score, ids}`).
    * `{:session, fun}`: change the selection or the clipboard, not the
      score (no undo step). `fun` takes and returns the
      `DrawMusic.Music.Session`.
    * `{:saved, version, message}`: the score was stored as `version`,
      which has its key and composition loaded. If it is the version being
      edited, the editor carries on with it. Otherwise the editor opens it.
      `message` tells the user.
    * `{:flash, kind, message}`: show a flash (`:info` or `:error`). A
      component's own flash wouldn't reach the page's layout.
    * `{:settings, {sf, mode}, fields}`: apply checked score settings (see
      `DrawMusicWeb.Editor.SettingsDialog`). A new key is confirmed first.
    * `{:transpose, {sf, mode}, direction}`: move the notes into the key,
      `:nearest`, `:up` or `:down`.
    * `{:palette, changes}`: the palette's new state, only what changed,
      out of `armed`, `row_kind` and `insert?` (see
      `DrawMusicWeb.Editor.Palette`).
    * `{:mode, :edit | :play}`: switch the editor to that mode.
    * `{:history, :undo | :redo}`: step back or forward through the edits.
  """

  alias DrawMusic.Library.Version

  @type key :: {-7..7, :major | :minor}

  @type edit :: (DrawMusic.Music.Score.t(), DrawMusic.Music.Context.t() -> term())

  @type t ::
          {:open, atom() | tuple()}
          | :close
          | {:edit, edit()}
          | {:edit, edit(), :select}
          | {:session, (DrawMusic.Music.Session.t() -> DrawMusic.Music.Session.t())}
          | {:saved, Version.t(), String.t()}
          | {:flash, :info | :error, String.t()}
          | {:settings, key(), map()}
          | {:transpose, key(), :nearest | :up | :down}
          | {:palette, palette_changes()}
          | {:mode, :edit | :play}
          | {:history, :undo | :redo}

  @typedoc "Changed palette state: any of `armed`, `row_kind` and `insert?`."
  @type palette_changes :: %{
          optional(:armed) => DrawMusicWeb.Armed.t() | nil,
          optional(:row_kind) => :note | :rest,
          optional(:insert?) => boolean()
        }

  @doc "Sends `intent` to the editor (the LiveView this process runs)."
  @spec notify(t()) :: {:editor, t()}
  def notify(intent), do: send(self(), {:editor, intent})
end
