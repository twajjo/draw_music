defmodule DrawMusicWeb.UserLive.Preferences do
  @moduledoc """
  The user's preferences (appearance, score display, reading aids) as a page
  of their own, for the account menu away from the editor. In the editor the
  same sections open as a panel over the score instead.

  The form (`DrawMusicWeb.PreferencesForm`) previews its changes here and
  stores them only on Save. Save and Cancel both leave the page, back to
  where it was opened from (the compositions page if there's nowhere to go
  back to): Save keeps the changes, Cancel discards them. Leaving any other
  way with changes not saved asks first.

  Unlike the account page (email and password), it needs no recent log-in.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.EditorComponents, only: [unsaved_guard: 1]
  import DrawMusicWeb.PreferencesComponents, only: [preference_sections: 1]

  alias DrawMusicWeb.PreferencesForm

  # A preview: the page follows it, and has changes not yet saved.
  @impl true
  def handle_info({PreferencesForm, {:preview, user}}, socket) do
    {:noreply,
     socket
     |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
     |> assign(:dirty?, user != socket.assigns.stored)}
  end

  # Saved or cancelled: nothing left unsaved, and the page is left.
  def handle_info({PreferencesForm, {_saved_or_cancelled, user}}, socket) do
    {:noreply,
     socket
     |> assign(current_scope: %{socket.assigns.current_scope | user: user}, dirty?: false)
     |> push_event("preferences:leave", %{to: ~p"/compositions"})}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Preferences",
       stored: socket.assigns.current_scope.user,
       dirty?: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} import_panel={@import_panel}>
      <div id="preferences-page" phx-hook=".LeavePreferences" class="space-y-4">
        <div class="text-center">
          <.header>
            Preferences
            <:subtitle>
              User's preferred editor appearance (individual score options are set in the editor)
            </:subtitle>
          </.header>
        </div>
        <.preference_sections scope={@current_scope} />
        <.unsaved_guard dirty?={@dirty?} />
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".LeavePreferences">
        // Save or Cancel leaves the page: back where it was opened from, or
        // to `to` when there's nowhere to go back to.
        export default {
          mounted() {
            this.handleEvent("preferences:leave", ({to}) => {
              if (window.history.length > 1) window.history.back()
              else window.location.assign(to)
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
