defmodule DrawMusicWeb.Editor.SaveAsDialog do
  @moduledoc """
  Saves the score as a new composition. It asks for the composition's name
  and credits, starting from the current one's credits and notes (see
  `DrawMusicWeb.EditorSaving.save_as_start/2`).

  A standalone LiveComponent: it owns its form, creates the composition
  itself and tells the editor the result through `DrawMusicWeb.Editor.Intent`.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:scope`: the signed-in user's `DrawMusic.Accounts.Scope` (required).
    * `:composition`: the `DrawMusic.Library.Composition` being edited
      (required).
    * `:version`: the `DrawMusic.Library.Version` being edited (required).
    * `:key`: the new composition's key, as `%{sf: sf, mode: mode}` (required).
    * `:version_attrs`: what the first version stores, as built by
      `DrawMusicWeb.EditorSettings.version_attrs/3` (required).

  ## Intents
    * `{:saved, version, message}`: the new composition's first version.
    * `:close`: Cancel, Esc or a click outside; nothing was saved.
    * `{:flash, :error, message}`: the version itself was refused.
  """

  use DrawMusicWeb, :live_component

  import DrawMusicWeb.LibraryComponents, only: [composition_fields: 1]

  alias DrawMusic.Accounts.Scope
  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Version}
  alias DrawMusicWeb.Editor.Intent
  alias DrawMusicWeb.EditorSaving

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("close", _params, socket) do
    Intent.notify(:close)
    {:noreply, socket}
  end

  def handle_event("save", %{"composition" => params}, socket) do
    %{scope: scope, key: key, version_attrs: attrs} = socket.assigns

    case Library.create_composition(scope, params, key, attrs) do
      {:ok, saved} ->
        Intent.notify({:saved, saved, "Saved"})
        {:noreply, socket}

      {:error, %Ecto.Changeset{data: %Composition{}} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}

      {:error, changeset} ->
        Intent.notify({:flash, :error, EditorSaving.error_message(changeset)})
        {:noreply, socket}
    end
  end

  def handle_event("validate", %{"composition" => params}, socket) do
    changeset = Library.change_composition(socket.assigns.scope, %Composition{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        id="save-as-dialog"
        role="dialog"
        aria-label="Save as a new composition"
        class="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <h2 class="text-lg font-semibold">Save as a new composition</h2>
        <.form
          for={@form}
          id="save-as-form"
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
  # editor leave what is being typed alone.
  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(
        %{
          scope: %Scope{},
          composition: %Composition{},
          version: %Version{},
          key: %{sf: _, mode: _},
          version_attrs: %{}
        } = assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :scope, :composition, :version, :key, :version_attrs]))
     |> assign_new(:form, fn %{scope: scope, composition: composition, version: version} ->
       to_form(
         Library.change_composition(scope, EditorSaving.save_as_start(composition, version))
       )
     end)}
  end

  def update(_assigns, _socket) do
    raise ArgumentError,
          "SaveAsDialog needs a :scope, :composition, :version, :key and :version_attrs"
  end

  attr :target, :any, required: true

  defp actions(assigns) do
    ~H"""
    <div class="flex justify-end gap-2 pt-2">
      <button type="button" phx-click="close" phx-target={@target} class="btn btn-ghost">
        Cancel
      </button>
      <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">Save</button>
    </div>
    """
  end
end
