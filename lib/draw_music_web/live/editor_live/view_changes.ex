defmodule DrawMusicWeb.EditorLive.ViewChanges do
  @moduledoc """
  How the editor shows the score (`DrawMusicWeb.Editor.View`) as it's
  switched or the user's preferences change: a `:handle_info` hook on
  `DrawMusicWeb.EditorLive` (`attach/1`) taking

    * `{LayoutToggle, {:chosen, layout}}`: Page / Strip, for this session;
    * `{PaperToggle, {:chosen, paper}}`: the Sheet button, for this session;
    * `{PreferencesForm, {:preview | :saved | :cancelled, user}}`: the
      Preferences panel's form; Save and Cancel close the panel.

  Other messages go on to the LiveView.
  """

  import Phoenix.Component, only: [assign: 2, update: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_patch: 2]

  alias DrawMusic.Accounts.User
  alias DrawMusicWeb.Editor.{Drawing, View}
  alias DrawMusicWeb.EditorLive.Edit
  alias DrawMusicWeb.{LayoutToggle, PaperToggle, PreferencesForm}
  alias Phoenix.LiveView.Socket

  @doc "Attaches the hook."
  @spec attach(Socket.t()) :: Socket.t()
  def attach(%Socket{} = socket), do: attach_hook(socket, :view_changes, :handle_info, &info/2)

  @doc """
  The editor in `user`'s preferences (stored or previewed): the view
  follows a changed preference, and the score is drawn again as far as it
  needs (`Drawing.basis/2`).
  """
  @spec follow_user(Socket.t(), User.t()) :: Socket.t()
  def follow_user(%Socket{} = socket, %User{} = user) do
    %{current_scope: scope, view: view} = socket.assigns
    new_view = View.follow(view, scope.user, user)

    socket
    |> assign(current_scope: %{scope | user: user}, view: new_view)
    |> redraw_for(Drawing.basis(scope.user, view), Drawing.basis(user, new_view))
  end

  # The palette's Page / Strip: the score in that layout, for this session
  # only (the preference stays as it is).
  defp info({LayoutToggle, {:chosen, layout}}, socket) do
    {:halt,
     socket
     |> update(:view, &%{&1 | layout: layout})
     |> Edit.assign_layout()}
  end

  # The Sheet button: the score on that paper, for this session only. The
  # colors are CSS (`data-paper`), so nothing is drawn again.
  defp info({PaperToggle, {:chosen, paper}}, socket) do
    {:halt, update(socket, :view, &%{&1 | paper: paper})}
  end

  # The form's preview; Save and Cancel close the panel (closing puts back
  # what's stored: `EditorLive.handle_params/3`).
  defp info({PreferencesForm, {:preview, user}}, socket) do
    {:halt, follow_user(socket, user)}
  end

  defp info({PreferencesForm, {_saved_or_cancelled, user}}, socket) do
    {:halt,
     socket
     |> follow_user(user)
     |> push_patch(to: socket.assigns.path, replace: true)}
  end

  defp info(_message, socket), do: {:cont, socket}

  # From what was drawn to what is: a new layout lays the score out again;
  # new reading aids redraw its pieces (the aids are in them).
  defp redraw_for(socket, same, same), do: socket

  defp redraw_for(socket, {layout, _old_aids}, {layout, _new_aids}),
    do: Edit.assign_pieces(socket)

  defp redraw_for(socket, _old, _new), do: Edit.assign_layout(socket)
end
