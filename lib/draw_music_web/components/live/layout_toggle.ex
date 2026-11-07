defmodule DrawMusicWeb.LayoutToggle do
  @moduledoc """
  Switches the user's score layout between page-style systems ("Page") and
  one long staff ("Strip"), and saves the choice as their preference.

  A standalone LiveComponent: it saves the preference itself and works in
  any LiveView.

  ## Inputs
    * `:id` — the component's id; each button's id is `"<id>-page"` or
      `"<id>-strip"`.
    * `:scope` — the signed-in user's `DrawMusic.Accounts.Scope` (required);
      its user's `score_layout` is the one shown as chosen.
    * `:class` — extra classes for the group (e.g. `contents`, so the buttons
      join the caller's grid).
    * `:button_class` — extra classes for each button.

  ## Messages to the parent
  Sent as `{DrawMusicWeb.LayoutToggle, message}`:
    * `{:updated, user}` — the new layout is saved. The parent puts `user`
      in its scope (and lays its score out again, if it shows one).

  ## Browser events
  Before asking for a different layout, it dispatches `"score:redraw"`
  (`detail: %{layout: layout}`) on the window, so a score on the page can
  say it's redrawing while the server lays it out again.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Accounts
  alias DrawMusic.Accounts.Scope

  @layouts [
    {:page, "Page", "Rows, like sheet music"},
    {:strip, "Strip", "One long staff"}
  ]

  @type message :: {:updated, DrawMusic.Accounts.User.t()}

  # A refused layout (only a tampered request) leaves the preference as it was.
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set", %{"layout" => layout}, socket) do
    case Accounts.update_user_preferences(socket.assigns.scope, %{score_layout: layout}) do
      {:ok, user} -> send(self(), {__MODULE__, {:updated, user}})
      {:error, _changeset} -> :ignored
    end

    {:noreply, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id={@id} class={["join", @class]} role="group" aria-label="Score layout">
      <.layout_button
        :for={{layout, label, hint} <- @layouts}
        id={"#{@id}-#{layout}"}
        layout={layout}
        label={label}
        hint={hint}
        current={@scope.user.score_layout}
        class={@button_class}
        target={@myself}
      />
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{scope: %Scope{}} = assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :scope]))
     |> assign(class: assigns[:class], button_class: assigns[:button_class], layouts: @layouts)}
  end

  def update(_assigns, _socket), do: raise(ArgumentError, "LayoutToggle needs a :scope")

  # Choosing the current layout again changes nothing to redraw.
  defp choose(layout, layout, target), do: JS.push("set", target: target)

  defp choose(_current, layout, target) do
    "score:redraw"
    |> JS.dispatch(detail: %{layout: layout})
    |> JS.push("set", target: target)
  end

  attr :id, :string, required: true
  attr :layout, :atom, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true
  attr :current, :atom, required: true
  attr :class, :string, default: nil
  attr :target, :any, required: true

  defp layout_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      title={@hint}
      aria-pressed={to_string(@current == @layout)}
      phx-click={choose(@current, @layout, @target)}
      phx-value-layout={@layout}
      class={[
        "join-item btn btn-sm transition-colors",
        @class,
        if(@current == @layout, do: "btn-primary", else: "btn-ghost")
      ]}
    >
      {@label}
    </button>
    """
  end
end
