defmodule DrawMusicWeb.DetailsDialog do
  @moduledoc """
  Changes a composition's details: its name, subtitle, credits and notes.
  They belong to the composition, so every key and version shares them.

  A standalone LiveComponent: it owns its form and its events, and works in
  any LiveView.

  ## Inputs
    * `:id` — the component's id (required by LiveView).
    * `:scope` — the signed-in user's `DrawMusic.Accounts.Scope` (required).
    * `:composition` — the `DrawMusic.Library.Composition` to change (required).
    * `:persist?` — whether saving stores the details at once (the
      default), or only checks them, for a draft that isn't saved yet.

  ## Messages to the parent
  Sent as `{DrawMusicWeb.DetailsDialog, message}`:
    * `{:saved, composition}` — the details were accepted (and stored, when
      `persist?`). The parent closes the dialog and shows the change.
    * `:closed` — Cancel, Esc or a click outside; nothing changed.
  """

  use DrawMusicWeb, :live_component

  import DrawMusicWeb.LibraryComponents, only: [composition_fields: 1]

  alias DrawMusic.Accounts.Scope
  alias DrawMusic.Library
  alias DrawMusic.Library.Composition

  @type message :: {:saved, Composition.t()} | :closed

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("close", _params, socket) do
    notify_parent(:closed)
    {:noreply, socket}
  end

  def handle_event("save", %{"composition" => params}, socket) do
    case store(socket.assigns, params) do
      {:ok, composition} ->
        notify_parent({:saved, composition})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :update))}
    end
  end

  def handle_event("validate", %{"composition" => params}, socket) do
    %{scope: scope, composition: composition} = socket.assigns
    changeset = Library.change_composition(scope, composition, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        id="details-dialog"
        role="dialog"
        aria-label="Composition details"
        class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <h2 class="text-lg font-semibold">Composition details</h2>
        <p class="mt-1 text-sm opacity-70">Shared by every key and version of this composition.</p>
        <.form
          for={@form}
          id="details-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
          class="mt-4 space-y-1"
        >
          <.composition_fields form={@form} />
          <.actions target={@myself} />
        </.form>
      </div>
    </div>
    """
  end

  # The form starts from the composition once; later updates from the
  # parent leave what is being typed alone.
  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{scope: %Scope{}, composition: %Composition{}} = assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :scope, :composition]))
     |> assign(:persist?, Map.get(assigns, :persist?, true))
     |> assign_new(:form, fn %{scope: scope, composition: composition} ->
       to_form(Library.change_composition(scope, composition))
     end)}
  end

  def update(_assigns, _socket) do
    raise ArgumentError, "DetailsDialog needs a :scope and a :composition"
  end

  attr :target, :any, required: true

  defp actions(assigns) do
    ~H"""
    <div class="flex justify-end gap-2 pt-3">
      <button type="button" phx-click="close" phx-target={@target} class="btn btn-ghost">
        Cancel
      </button>
      <button id="details-save" type="submit" class="btn btn-primary" phx-disable-with="Saving...">
        Save
      </button>
    </div>
    """
  end

  defp notify_parent(message), do: send(self(), {__MODULE__, message})

  # A draft's details are only checked: they are stored with its first save.
  defp store(%{persist?: false, scope: scope, composition: composition}, params) do
    scope
    |> Library.change_composition(composition, params)
    |> Ecto.Changeset.apply_action(:update)
  end

  defp store(%{scope: scope, composition: composition}, params) do
    Library.update_composition(scope, composition, params)
  end
end
