defmodule DrawMusicWeb.UserLive.Preferences do
  @moduledoc """
  The user's preferences (appearance, score display, reading aids) as a page
  of their own, for the account menu away from the editor. In the editor the
  same sections open as a panel over the score instead.

  Unlike the account page (email and password), it needs no recent log-in.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.PreferencesComponents, only: [preference_sections: 1]

  alias DrawMusicWeb.{InkPicker, LayoutToggle, PreferenceSwitch}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Preferences
          <:subtitle>
            User's preferred editor appearance (individual score options are set in the editor)
          </:subtitle>
        </.header>
      </div>
      <.preference_sections scope={@current_scope} />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Preferences")}

  # A saved preference: the page (and its ink) follows the new user.
  @impl true
  def handle_info({component, {:updated, user}}, socket)
      when component in [InkPicker, LayoutToggle, PreferenceSwitch] do
    {:noreply, assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})}
  end
end
