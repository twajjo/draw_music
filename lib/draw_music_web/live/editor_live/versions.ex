defmodule DrawMusicWeb.EditorLive.Versions do
  @moduledoc """
  What changes the version beside its notes, and saving it: a
  `:handle_info` hook on `DrawMusicWeb.EditorLive` (`attach/1`) taking the
  components' intents (`DrawMusicWeb.Editor.Intent`)

    * `{:settings, key, fields}`: Score settings apply at once; a new key
      waits for the transpose dialog;
    * `{:transpose, key, direction}` and `{:rekey, key}`: the score in
      another key (on a saved version, stored as a new version in it);
    * `{:instrument, program}`: the playback instrument made the version's;
    * `{:saved, version, message}`: stored; a new version or composition
      opens.

  Play mode doesn't change the settings or the key. Other messages go on
  to the LiveView.
  """

  import DrawMusicWeb.LibraryComponents, only: [version_path: 3]
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_navigate: 2, put_flash: 3]

  alias DrawMusic.Library
  alias DrawMusic.Library.{Key, Version}
  alias DrawMusic.Music.{Context, Rekey, Session, Transpose}
  alias DrawMusicWeb.Editor.{Messages, VersionExtras}
  alias DrawMusicWeb.EditorLive.Edit
  alias DrawMusicWeb.{EditorSaving, EditorSettings}
  alias Phoenix.LiveView.Socket

  @doc "Attaches the hook."
  @spec attach(Socket.t()) :: Socket.t()
  def attach(%Socket{} = socket), do: attach_hook(socket, :versions, :handle_info, &info/2)

  defp apply_settings(socket, key, fields) do
    case EditorSettings.apply(socket.assigns.session, fields) do
      {:ok, session} ->
        %{extras: old} = socket.assigns
        extras = %VersionExtras{tempo_text: fields.tempo_text, instrument: fields.instrument}

        socket
        |> assign(
          session: touched(session, extras, old),
          dialog: transpose_prompt(key, session.ctx)
        )
        |> assign(:extras, extras)
        |> Edit.assign_layout()

      {:error, reason} ->
        put_flash(socket, :error, Messages.refused(reason))
    end
  end

  # A key change on a saved version is stored as a new version in that key;
  # on the draft it just applies.
  defp in_new_key(%{assigns: %{version: %Version{id: nil}}} = socket, _sf, _mode) do
    Edit.assign_layout(socket)
  end

  defp in_new_key(socket, sf, mode) do
    %{current_scope: scope, composition: composition, version: old} = socket.assigns
    attrs = EditorSettings.version_attrs(socket.assigns.session, socket.assigns.extras)

    case Library.save_in_key(scope, composition, %{sf: sf, mode: mode}, attrs) do
      {:ok, saved} ->
        message =
          "Saved as #{Key.name(sf, mode)} v#{saved.number} " <>
            "(#{Key.name(old.key)} v#{old.number} is kept)"

        saved_and_open(socket, saved, message)

      {:error, changeset} ->
        put_flash(socket, :error, EditorSaving.error_message(changeset))
    end
  end

  # Play mode doesn't change the score's settings or its key.
  defp info({:editor, {intent, _key, _value}}, %{assigns: %{editor_mode: :play}} = socket)
       when intent in [:settings, :transpose] do
    {:halt, socket}
  end

  # Settings apply at once; a new key is confirmed in the transpose dialog.
  defp info({:editor, {:settings, key, fields}}, socket) do
    {:halt, apply_settings(socket, key, fields)}
  end

  # Suggest key: the same sounds in the chosen key, saved in it as a new key
  # change would be.
  defp info({:editor, {:rekey, {sf, mode}}}, socket) do
    %{session: session} = socket.assigns
    score = Rekey.to_signature(session.score, sf)
    session = Session.change_context(session, %{session.ctx | sf: sf, mode: mode}, score)

    {:halt,
     socket
     |> assign(:session, session)
     |> in_new_key(sf, mode)}
  end

  defp info({:editor, {:transpose, {sf, mode}, direction}}, socket) do
    %{session: session} = socket.assigns
    from = {session.ctx.sf, session.ctx.mode}
    socket = assign(socket, :dialog, nil)

    case Transpose.to_key(session.score, from, {sf, mode}, direction) do
      {:ok, score} ->
        session = Session.change_context(session, %{session.ctx | sf: sf, mode: mode}, score)

        {:halt,
         socket
         |> assign(:session, session)
         |> in_new_key(sf, mode)}

      {:error, reason} ->
        {:halt, put_flash(socket, :error, Messages.refused(reason))}
    end
  end

  # The playback instrument, made the version's: unsaved work until saved.
  defp info({:editor, {:instrument, program}}, socket) do
    %{session: session, extras: extras} = socket.assigns

    {:halt,
     assign(socket,
       session: touched(session, program, extras.instrument),
       extras: %{extras | instrument: program}
     )}
  end

  # The version being edited was stored: carry on with it.
  defp info(
         {:editor, {:saved, %Version{id: id} = saved, message}},
         %{assigns: %{version: %Version{id: id}}} = socket
       ) do
    {:halt,
     socket
     |> assign(version: saved, session: Session.saved(socket.assigns.session))
     |> put_flash(:info, message)}
  end

  # A new version or composition: open it.
  defp info({:editor, {:saved, saved, message}}, socket) do
    {:halt, saved_and_open(socket, saved, message)}
  end

  defp info(_message, socket), do: {:cont, socket}

  defp saved_and_open(socket, saved, message) do
    socket
    |> assign(:session, Session.saved(socket.assigns.session))
    |> put_flash(:info, message)
    |> push_navigate(to: version_path(saved.key.composition.id, saved.key, saved.number))
  end

  # The marking and instrument live beside the session; changing them is
  # still unsaved work.
  defp touched(session, same, same), do: session
  defp touched(session, _new, _old), do: %{session | dirty?: true}

  # A key other than the current one waits for the transpose dialog; the
  # same key closes the settings with nothing more to ask.
  defp transpose_prompt({sf, mode}, %Context{sf: sf, mode: mode}), do: nil
  defp transpose_prompt(key, _ctx), do: {:transpose, key}
end
