defmodule DrawMusicWeb.PaperToggle do
  @moduledoc """
  The **Sheet** button: switches a score's paper between black on white and
  the user's ink on black. It shows the paper in use, the way the Insert /
  Overlay button shows its mode: "Sheet" in black on white, or in the ink on
  black. It's a view choice: it stores nothing, and the parent decides how
  long it lasts (the editor: the session). The ink itself is set only in
  Preferences.

  A standalone LiveComponent that works in any LiveView. Its colors are the
  score's (`--score-paper`, `--score-ink`), so the parent draws it inside
  the paper it names.

  ## Inputs
    * `:id`: the button's id.
    * `:paper`: the paper shown now, `:white` or `:black`.
    * `:class`: extra classes for the button.

  ## Messages to the parent
  Sent as `{DrawMusicWeb.PaperToggle, message}`:
    * `{:chosen, paper}`: the other paper was picked. The parent shows its
      score on it.
  """

  use DrawMusicWeb, :live_component

  @type message :: {:chosen, :white | :black}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("toggle", _params, socket) do
    send(self(), {__MODULE__, {:chosen, other(socket.assigns.paper)}})
    {:noreply, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      title={title(@paper)}
      data-paper={@paper}
      phx-click="toggle"
      phx-target={@myself}
      class={[
        "btn btn-sm border-base-300 bg-[var(--score-paper)] text-[var(--score-ink)] shadow-sm transition-colors hover:-translate-y-px",
        @class
      ]}
    >
      Sheet
    </button>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{paper: paper} = assigns, socket) when paper in [:white, :black] do
    {:ok, assign(socket, id: assigns.id, paper: paper, class: assigns[:class])}
  end

  def update(_assigns, _socket), do: raise(ArgumentError, "PaperToggle needs a :paper")

  defp other(:white), do: :black
  defp other(:black), do: :white

  defp title(:white), do: "The score is black on white; click for your ink on black"
  defp title(:black), do: "The score is your ink on black; click for black on white"
end
