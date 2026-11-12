defmodule DrawMusicWeb.Editor.SettingsDialog do
  @moduledoc """
  The score's settings: key, time signature, tempo, pickup and instrument.

  A standalone LiveComponent: it owns its form and checks it (see
  `DrawMusicWeb.EditorSettings.validate/1`). The editor applies settings
  that pass, so they can be undone with the rest of the score's changes.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:ctx`: the score's `DrawMusic.Music.Context` (required).
    * `:tempo_text`: the tempo marking (required).
    * `:instrument`: the version's GM program, 0..127 (required).

  ## Intents
    * `{:settings, {sf, mode}, fields}`: settings that passed. `{sf, mode}`
      is the chosen key, and `fields` holds the Context fields they set
      plus `:tempo_text` and `:instrument`.
    * `:close`: Cancel, Esc or a click outside; nothing changed.
  """

  use DrawMusicWeb, :live_component

  import DrawMusicWeb.LibraryComponents, only: [score_settings_fields: 1]

  alias DrawMusic.Music.Context
  alias DrawMusicWeb.Editor.Intent
  alias DrawMusicWeb.EditorSettings

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("apply", %{"settings" => params}, socket) do
    case EditorSettings.validate(params) do
      {:ok, key, fields} ->
        Intent.notify({:settings, key, fields})
        {:noreply, socket}

      {:error, errors} ->
        form = to_form(params, as: :settings, errors: errors, action: :validate)
        {:noreply, assign(socket, :form, form)}

      :error ->
        {:noreply, socket}
    end
  end

  # The fields follow what is being chosen (the time decides whether a
  # symbol can be chosen and how long the pickup can be, a marking which
  # words can be printed); nothing is checked until Apply.
  def handle_event("change", %{"settings" => params}, socket) do
    form = to_form(EditorSettings.follow(params), as: :settings)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("close", _params, socket) do
    Intent.notify(:close)
    {:noreply, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        id="settings-dialog"
        role="dialog"
        aria-label="Score settings"
        class="w-full max-w-3xl rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <h2 class="text-lg font-semibold">Score settings</h2>
        <.form
          for={@form}
          id="settings-form"
          phx-change="change"
          phx-submit="apply"
          phx-target={@myself}
          class="mt-4 grid gap-x-4 sm:grid-cols-2"
        >
          <.score_settings_fields form={@form} />
          <.actions target={@myself} />
        </.form>
      </div>
    </div>
    """
  end

  # The form starts from the score's settings once; later updates from the
  # editor leave what is being typed alone.
  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{ctx: %Context{} = ctx, instrument: instrument} = assigns, socket)
      when instrument in 0..127 do
    tempo_text = Map.get(assigns, :tempo_text)

    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign_new(:form, fn ->
       to_form(EditorSettings.params(ctx, tempo_text, instrument), as: :settings)
     end)}
  end

  def update(_assigns, _socket) do
    raise ArgumentError, "SettingsDialog needs a :ctx and an :instrument"
  end

  attr :target, :any, required: true

  defp actions(assigns) do
    ~H"""
    <div class="flex justify-end gap-2 pt-2 sm:col-span-2">
      <button type="button" phx-click="close" phx-target={@target} class="btn btn-ghost">
        Cancel
      </button>
      <button id="settings-apply" type="submit" class="btn btn-primary">Apply</button>
    </div>
    """
  end
end
