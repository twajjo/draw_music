defmodule DrawMusicWeb.ComponentHostLive do
  @moduledoc """
  A bare LiveView for testing one LiveComponent on its own, away from the
  pages that use it. Mount it with `live_isolated/3`:

      live_isolated(conn, ComponentHostLive,
        session: %{"component" => DetailsDialog, "attrs" => %{scope: scope}, "test_pid" => self()}
      )

  The component is rendered with id `"subject"` and the given attrs. Every
  message it sends to its parent is passed on to the test as
  `{:component_sent, message}`, so the test can assert on what the
  component reported.
  """

  use DrawMusicWeb, :live_view

  @impl true
  def handle_info(message, socket) do
    send(socket.assigns.test_pid, {:component_sent, message})
    {:noreply, socket}
  end

  @impl true
  def mount(_params, %{"component" => component, "attrs" => attrs, "test_pid" => pid}, socket) do
    {:ok, assign(socket, component: component, attrs: attrs, test_pid: pid)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={@component} id="subject" {@attrs} />
    """
  end
end
