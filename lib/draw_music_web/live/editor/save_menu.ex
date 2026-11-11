defmodule DrawMusicWeb.Editor.SaveMenu do
  @moduledoc """
  Save, with a menu for Save as new version (stored versions only) and Save
  as new composition, and a dot when there are unsaved changes.

  A standalone LiveComponent: it stores the score itself and tells the
  editor the result through `DrawMusicWeb.Editor.Intent`.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:scope`: the signed-in user's `DrawMusic.Accounts.Scope` (required).
    * `:version`: the `DrawMusic.Library.Version` being edited, with its
      key loaded. Its `id` is `nil` on the draft (required).
    * `:version_attrs`: what a save stores (the score, its settings,
      tempo and instrument), as built by
      `DrawMusicWeb.EditorSettings.version_attrs/3` (required).
    * `:dirty?`: whether there are unsaved changes (default `false`).

  ## Intents
    * `{:saved, version, message}`: after Save or Save as new version.
    * `{:open, :save_as}`: Save as new composition, or Save on the draft,
      which has no composition to save into yet.
    * `{:flash, :error, message}`: the save was refused.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Accounts.Scope
  alias DrawMusic.Library
  alias DrawMusic.Library.Version
  alias DrawMusicWeb.Editor.Intent
  alias DrawMusicWeb.EditorSaving

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("open_save_as", _params, socket) do
    Intent.notify({:open, :save_as})
    {:noreply, socket}
  end

  # On the draft, Save means "save as a new composition".
  def handle_event("save", _params, %{assigns: %{version: %Version{id: nil}}} = socket) do
    Intent.notify({:open, :save_as})
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    %{scope: scope, version: version, version_attrs: attrs} = socket.assigns

    case Library.save_version(scope, version, attrs) do
      {:ok, saved} -> Intent.notify({:saved, %{saved | key: version.key}, "Saved"})
      {:error, changeset} -> refused(changeset)
    end

    {:noreply, socket}
  end

  def handle_event(
        "save_new_version",
        _params,
        %{assigns: %{version: %Version{id: nil}}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("save_new_version", _params, socket) do
    %{scope: scope, version: version, version_attrs: attrs} = socket.assigns

    case Library.save_new_version(scope, version.key, attrs) do
      {:ok, saved} -> Intent.notify({:saved, saved, "Saved as version #{saved.number}"})
      {:error, changeset} -> refused(changeset)
    end

    {:noreply, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="flex items-stretch gap-1">
      <.dirty_marker :if={@dirty?} />
      <div class="join">
        <button
          id="save"
          type="button"
          phx-click="save"
          phx-target={@myself}
          class="join-item btn btn-primary btn-sm h-auto"
        >
          Save
        </button>
        <.more_ways saved?={@version.id != nil} target={@myself} />
      </div>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{scope: %Scope{}, version: %Version{}, version_attrs: %{}} = assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :scope, :version, :version_attrs]))
     |> assign(:dirty?, Map.get(assigns, :dirty?, false))}
  end

  def update(_assigns, _socket) do
    raise ArgumentError, "SaveMenu needs a :scope, a :version and its :version_attrs"
  end

  defp dirty_marker(assigns) do
    ~H"""
    <span
      id="dirty-marker"
      title="Unsaved changes"
      class="size-2 self-center rounded-full bg-warning"
      aria-label="Unsaved changes"
    />
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :target, :any, required: true
  slot :inner_block, required: true

  defp menu_item(assigns) do
    ~H"""
    <li>
      <button
        id={@id}
        type="button"
        phx-click={@event}
        phx-target={@target}
        class="w-full rounded px-2 py-1.5 text-left transition-colors hover:bg-base-200"
      >
        {render_slot(@inner_block)}
      </button>
    </li>
    """
  end

  attr :saved?, :boolean, required: true, doc: "whether this is a stored version (not the draft)"
  attr :target, :any, required: true

  defp more_ways(assigns) do
    ~H"""
    <details id="save-menu" class="dropdown dropdown-end join-item flex">
      <summary class="btn btn-primary btn-sm btn-square h-auto" aria-label="More ways to save">
        <.icon name="hero-chevron-down-micro" class="size-4" />
      </summary>
      <ul class="dropdown-content z-30 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 text-sm shadow-lg">
        <.menu_item :if={@saved?} id="save-new-version" event="save_new_version" target={@target}>
          Save as new version
        </.menu_item>
        <.menu_item id="save-as" event="open_save_as" target={@target}>
          Save as new composition…
        </.menu_item>
      </ul>
    </details>
    """
  end

  defp refused(changeset) do
    Intent.notify({:flash, :error, EditorSaving.error_message(changeset)})
  end
end
