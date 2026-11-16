defmodule DrawMusicWeb.LayoutToggle do
  @moduledoc """
  Switches a score's layout between page-style systems ("Page") and one long
  staff ("Strip"). It's a view choice: it stores nothing, and the parent
  decides how long it lasts (the editor: the session).

  A standalone LiveComponent that works in any LiveView.

  ## Inputs
    * `:id`: the component's id; each button's id is `"<id>-page"` or
      `"<id>-strip"`.
    * `:layout`: the layout shown now (`:page` or `:strip`), drawn as chosen.
    * `:class`: extra classes for the group (e.g. `contents`, so the buttons
      join the caller's grid).
    * `:button_class`: extra classes for each button.

  ## Messages to the parent
  Sent as `{DrawMusicWeb.LayoutToggle, message}`:
    * `{:chosen, layout}`: a different layout was picked. The parent shows
      its score in it.

  ## Browser events
  Before asking for a different layout, it dispatches `"score:redraw"`
  (`detail: %{layout: layout}`) on the window, so a score on the page can
  say it's redrawing while the server lays it out again.
  """

  use DrawMusicWeb, :live_component

  @layouts [
    {:page, "Page", "Rows, like sheet music"},
    {:strip, "Strip", "One long staff"}
  ]

  @type message :: {:chosen, :page | :strip}

  # Only the two layouts are taken (anything else is a tampered request).
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set", %{"layout" => layout}, socket) when layout in ["page", "strip"] do
    send(self(), {__MODULE__, {:chosen, String.to_existing_atom(layout)}})
    {:noreply, socket}
  end

  def handle_event("set", _params, socket), do: {:noreply, socket}

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
        current={@layout}
        class={@button_class}
        target={@myself}
      />
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{layout: layout} = assigns, socket) when layout in [:page, :strip] do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :layout]))
     |> assign(class: assigns[:class], button_class: assigns[:button_class], layouts: @layouts)}
  end

  def update(_assigns, _socket), do: raise(ArgumentError, "LayoutToggle needs a :layout")

  # The current layout again changes nothing.
  defp choose(layout, layout, _target), do: nil

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
