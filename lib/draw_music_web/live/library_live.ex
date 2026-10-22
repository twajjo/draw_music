defmodule DrawMusicWeb.LibraryLive do
  @moduledoc "The signed-in user's compositions, with their keys and versions."

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.LibraryComponents

  alias DrawMusic.Library

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Compositions
        <:actions>
          <.button id="new-composition" variant="primary" navigate={~p"/compositions/new"}>
            <.icon name="hero-plus" class="size-4" /> New composition
          </.button>
        </:actions>
      </.header>

      <div id="compositions" phx-update="stream" class="space-y-3">
        <p id="compositions-empty" class="hidden only:block py-10 text-center opacity-60">
          No compositions yet. Start one with “New composition”.
        </p>
        <.composition_row
          :for={{id, composition} <- @streams.compositions}
          id={id}
          composition={composition}
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    compositions = Library.list_compositions(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Compositions")
     |> stream(:compositions, compositions)}
  end
end
