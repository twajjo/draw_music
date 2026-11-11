defmodule DrawMusicWeb.Editor.TransposeDialog do
  @moduledoc """
  Asks how to move the notes into a newly chosen key: to the nearest
  position, up or down.

  A standalone LiveComponent: the editor does the transposing, since it
  changes the score (and, on a stored version, saves it in the new key).

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:key`: the chosen key, as `{sf, mode}` (required).

  ## Intents
    * `{:transpose, {sf, mode}, direction}`: move the notes into the key,
      `:nearest`, `:up` or `:down`.
    * `:close`: Cancel; the key stays as it was.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Library.Key
  alias DrawMusicWeb.Editor.Intent

  @directions %{"nearest" => :nearest, "up" => :up, "down" => :down}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("close", _params, socket) do
    Intent.notify(:close)
    {:noreply, socket}
  end

  def handle_event("transpose", %{"direction" => dir}, socket) do
    case Map.fetch(@directions, dir) do
      {:ok, direction} -> Intent.notify({:transpose, socket.assigns.key, direction})
      :error -> :ok
    end

    {:noreply, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="transpose-dialog" class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        role="dialog"
        aria-label="Transpose"
        class="w-full max-w-sm rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
      >
        <h2 class="text-lg font-semibold">Transpose to {key_name(@key)}?</h2>
        <p class="mt-1 text-sm opacity-70">The notes move with the key.</p>
        <div class="mt-4 flex flex-wrap gap-2">
          <.direction dir="nearest" label="Nearest" primary target={@myself} />
          <.direction dir="up" label="Up" target={@myself} />
          <.direction dir="down" label="Down" target={@myself} />
          <button
            id="transpose-cancel"
            type="button"
            phx-click="close"
            phx-target={@myself}
            class="btn btn-ghost ml-auto"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{key: {sf, mode}} = assigns, socket)
      when sf in -7..7 and mode in [:major, :minor] do
    {:ok, assign(socket, Map.take(assigns, [:id, :key]))}
  end

  def update(_assigns, _socket), do: raise(ArgumentError, "TransposeDialog needs a :key")

  # One way to move the notes.
  attr :dir, :string, required: true
  attr :label, :string, required: true
  attr :primary, :boolean, default: false
  attr :target, :any, required: true

  defp direction(assigns) do
    ~H"""
    <button
      id={"transpose-#{@dir}"}
      type="button"
      phx-click="transpose"
      phx-value-direction={@dir}
      phx-target={@target}
      class={["btn", if(@primary, do: "btn-primary", else: "btn-ghost")]}
    >
      {@label}
    </button>
    """
  end

  defp key_name({sf, mode}), do: Key.name(sf, mode)
end
