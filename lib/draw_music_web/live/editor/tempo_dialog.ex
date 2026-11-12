defmodule DrawMusicWeb.Editor.TempoDialog do
  @moduledoc """
  Adds or edits a tempo change: its tempo, and for a rit. or accel. the
  tempo it reaches (shown as rit. or accel.) and over how many beats, at
  most up to the next change or the score's end.

  A standalone LiveComponent: it owns its form and checks it as it is
  typed (see `DrawMusicWeb.TempoForm`).

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:target`: the `DrawMusicWeb.TempoTarget` it edits (required).
    * `:ctx`: the score's `DrawMusic.Music.Context`, for its beats (required).

  ## Intents
    * `{:edit, fun, :select}`: Save puts the change, which is then selected.
    * `{:edit, fun}`: Delete removes the change (an existing one only).
    * `:close`: after either, and on Cancel, Esc or a click outside.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Music.{Context, TempoEditing}
  alias DrawMusicWeb.Editor.Intent
  alias DrawMusicWeb.{TempoForm, TempoTarget}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("close", _params, socket) do
    Intent.notify(:close)
    {:noreply, socket}
  end

  def handle_event("delete", _params, %{assigns: %{target: %TempoTarget{id: id}}} = socket)
      when is_binary(id) do
    Intent.notify({:edit, remove(id)})
    Intent.notify(:close)
    {:noreply, socket}
  end

  def handle_event("save", %{"tempo" => params}, socket) do
    %{target: target, ctx: ctx} = socket.assigns

    case TempoForm.validate(params, target, ctx) do
      {:ok, change} ->
        Intent.notify({:edit, put(%{change | id: change.id || Ecto.UUID.generate()}), :select})
        Intent.notify(:close)
        {:noreply, socket}

      {:error, errors} ->
        {:noreply, assign_form(socket, params, errors)}
    end
  end

  # Errors show as the values are typed.
  def handle_event("validate", %{"tempo" => params}, socket) do
    %{target: target, ctx: ctx} = socket.assigns

    errors =
      case TempoForm.validate(params, target, ctx) do
        {:ok, _change} -> []
        {:error, errors} -> errors
      end

    {:noreply, assign_form(socket, params, errors)}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assign(assigns,
        gradual?: assigns.form[:gradual].value == "true",
        ramp: TempoForm.ramp_word(assigns.form.params)
      )

    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        id="tempo-dialog"
        role="dialog"
        aria-label="Tempo change"
        class="w-full max-w-sm rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <h2 class="text-lg font-semibold">
          {if @target.id, do: "Tempo change", else: "New tempo change"}
        </h2>
        <.form
          for={@form}
          id="tempo-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
          class="mt-4"
        >
          <.input field={@form[:bpm]} type="number" label="Tempo (BPM)" />
          <.input
            field={@form[:gradual]}
            type="checkbox"
            label="Gradually (rit. or accel.)"
            checked={@gradual?}
          />
          <.gradual_fields :if={@gradual?} form={@form} ramp={@ramp} target={@target} />
          <.actions target={@target} myself={@myself} />
        </.form>
      </div>
    </div>
    """
  end

  # The form starts from the target's params once; later updates from the
  # editor leave what is being typed alone.
  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{target: %TempoTarget{} = target, ctx: %Context{} = ctx} = assigns, socket) do
    {:ok,
     socket
     |> assign(id: assigns.id, target: target, ctx: ctx)
     |> assign_new(:form, fn -> to_form(target.params, as: :tempo) end)}
  end

  def update(_assigns, _socket) do
    raise ArgumentError, "TempoDialog needs a :target and a :ctx"
  end

  attr :target, TempoTarget, required: true
  attr :myself, :any, required: true

  # Delete (an existing change only), Cancel and Save.
  defp actions(assigns) do
    ~H"""
    <div class="flex items-center gap-2 pt-2">
      <button
        :if={@target.id}
        id="tempo-delete"
        type="button"
        phx-click="delete"
        phx-target={@myself}
        class="btn btn-ghost text-error"
      >
        Delete
      </button>
      <button type="button" phx-click="close" phx-target={@myself} class="btn btn-ghost ml-auto">
        Cancel
      </button>
      <button id="tempo-save" type="submit" class="btn btn-primary">Save</button>
    </div>
    """
  end

  defp assign_form(socket, params, errors) do
    assign(socket, :form, to_form(params, as: :tempo, errors: errors, action: :validate))
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :ramp, :string, default: nil
  attr :target, TempoTarget, required: true

  # A rit.'s or accel.'s end tempo and length, with what it does and how
  # long it may last.
  defp gradual_fields(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-x-4">
      <.input field={@form[:to_bpm]} type="number" label="Reaching (BPM)" />
      <.input
        field={@form[:beats]}
        type="number"
        step="any"
        min="0"
        max={@target.max_beats}
        label="Over (beats)"
      />
      <p id="tempo-ramp" class="text-sm opacity-70">{ramp_hint(@ramp)}</p>
      <p id="tempo-room" class="text-sm opacity-70">
        {room_hint(@target.max_beats, @target.until)}
      </p>
    </div>
    """
  end

  defp put(change) do
    fn score, ctx ->
      with {:ok, score} <- TempoEditing.put(score, ctx, change), do: {:ok, score, [change.id]}
    end
  end

  # What a gradual change does, once its two tempos are known.
  defp ramp_hint(nil), do: "Set a tempo to reach"
  defp ramp_hint("rit."), do: "rit.: slowing down"
  defp ramp_hint("accel."), do: "accel.: speeding up"

  defp remove(id) do
    fn score, _ctx -> {:ok, TempoEditing.remove(score, [id])} end
  end

  defp room_end(:next_change), do: "up to the next tempo change"
  defp room_end(:score_end), do: "up to the end of the score"

  # How long a gradual change may last, e.g. "At most 3 beats, up to the next tempo change".
  defp room_hint(max_beats, until) do
    "At most #{max_beats} #{if max_beats == "1", do: "beat", else: "beats"}, #{room_end(until)}"
  end
end
