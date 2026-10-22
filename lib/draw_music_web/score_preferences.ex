defmodule DrawMusicWeb.ScorePreferences do
  @moduledoc """
  Saves the score display preferences from the controls in
  `DrawMusicWeb.SettingsComponents`, for any LiveView showing them. On
  success the socket's `current_scope` carries the updated user, so the
  layout and ink (see `Layouts.app`) update at once; on failure
  `:preferences_form` holds the errors.
  """

  import Phoenix.Component, only: [assign: 3, to_form: 1]

  alias DrawMusic.Accounts

  @doc "The preferences form for the socket's user."
  def form(scope), do: scope |> Accounts.change_user_preferences() |> to_form()

  @doc """
  Applies a `set_score_layout` or `set_score_ink` event's params to the
  user's preferences; returns the socket.
  """
  def apply_event("set_score_layout", %{"layout" => layout}, socket),
    do: update(socket, %{score_layout: layout})

  def apply_event("set_score_ink", %{"color" => color}, socket),
    do: update(socket, %{score_ink_dark: color})

  defp update(socket, attrs) do
    scope = socket.assigns.current_scope

    case Accounts.update_user_preferences(scope, attrs) do
      {:ok, user} ->
        scope = %{scope | user: user}

        socket
        |> assign(:current_scope, scope)
        |> assign(:preferences_form, form(scope))

      {:error, changeset} ->
        assign(socket, :preferences_form, to_form(%{changeset | action: :update}))
    end
  end
end
