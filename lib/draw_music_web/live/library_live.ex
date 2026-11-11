defmodule DrawMusicWeb.LibraryLive do
  @moduledoc """
  The signed-in user's compositions, with their keys and versions. Importing
  a .mid file is done by `DrawMusicWeb.ImportDialog`, and editing a
  composition's details by `DrawMusicWeb.DetailsDialog`.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.LibraryComponents

  alias DrawMusic.Library
  alias DrawMusicWeb.{DetailsDialog, ImportDialog}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Compositions
        <:actions>
          <.button id="import-open" phx-click="open_import">
            <.icon name="hero-arrow-up-tray" class="size-4" /> Import .mid
          </.button>
          <.button id="new-composition" variant="primary" navigate={~p"/compositions/new"}>
            <.icon name="hero-plus" class="size-4" /> New composition
          </.button>
        </:actions>
      </.header>

      <div id="compositions" phx-update="stream" class="space-y-3">
        <p id="compositions-empty" class="hidden only:block py-10 text-center opacity-60">
          No compositions yet. Start one with “New composition”, or import a .mid file.
        </p>
        <.composition_row
          :for={{id, composition} <- @streams.compositions}
          id={id}
          composition={composition}
        />
      </div>

      <.live_component
        :if={@importing?}
        module={ImportDialog}
        id="import"
        scope={@current_scope}
      />

      <.live_component
        :if={@details_composition}
        module={DetailsDialog}
        id="details"
        scope={@current_scope}
        composition={@details_composition}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    compositions = Library.list_compositions(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Compositions")
     |> assign(:details_composition, nil)
     |> assign(:importing?, false)
     |> stream(:compositions, compositions)}
  end

  @impl true
  def handle_event("open_import", _params, socket) do
    {:noreply, assign(socket, :importing?, true)}
  end

  ## Details

  def handle_event("edit_details", %{"id" => id}, socket) when is_binary(id) do
    composition = Library.get_composition!(socket.assigns.current_scope, id)
    {:noreply, assign(socket, :details_composition, composition)}
  end

  ## Versions

  # The browser asked first (data-confirm). The composition's only version
  # takes the composition with it.
  def handle_event("delete_version", %{"id" => id}, socket) when is_binary(id) do
    scope = socket.assigns.current_scope
    version = Library.get_version!(scope, id)
    composition = version.key.composition

    case Library.delete_version(scope, version) do
      {:ok, _version} ->
        {:noreply,
         socket
         |> stream_insert(:compositions, Library.get_composition!(scope, composition.id))
         |> put_flash(:info, "Version deleted.")}

      {:error, :last_version} ->
        {:ok, _composition} = Library.delete_composition(scope, composition)

        {:noreply,
         socket
         |> stream_delete(:compositions, composition)
         |> put_flash(:info, "#{composition.name} deleted.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "That version couldn't be deleted.")}
    end
  end

  # The details dialog's results: the row shows the new details at once.
  @impl true
  def handle_info({DetailsDialog, {:saved, composition}}, socket) do
    scope = socket.assigns.current_scope

    {:noreply,
     socket
     |> assign(:details_composition, nil)
     |> stream_insert(:compositions, Library.get_composition!(scope, composition.id))
     |> put_flash(:info, "Details saved.")}
  end

  def handle_info({DetailsDialog, :closed}, socket) do
    {:noreply, assign(socket, :details_composition, nil)}
  end

  # The import dialog's results: a stored piece opens in the editor.
  def handle_info({ImportDialog, {:imported, version}}, socket) do
    path = version_path(version.key.composition_id, version.key, version.number)
    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({ImportDialog, :closed}, socket) do
    {:noreply, assign(socket, :importing?, false)}
  end
end
