defmodule DrawMusicWeb.InkPicker do
  @moduledoc """
  Picks the notation color used in dark mode, from preset swatches or any
  custom color, and saves it as the user's preference. A color too dark to
  read on black is refused, with the reason shown under the picker.

  A standalone LiveComponent: it saves the preference itself, keeps its own
  errors, and works in any LiveView.

  ## Inputs
    * `:id` — the component's id; each swatch's id is `"<id>-<rrggbb>"` and
      the custom color form's is `"<id>-custom"`.
    * `:scope` — the signed-in user's `DrawMusic.Accounts.Scope` (required);
      its user's `score_ink_dark` is shown as chosen (nil means white).

  ## Messages to the parent
  Sent as `{DrawMusicWeb.InkPicker, message}`:
    * `{:updated, user}` — the new color is saved. The parent puts `user` in
      its scope, so the page's ink changes at once.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Accounts
  alias DrawMusic.Accounts.Scope

  @presets [
    {"White", "#ffffff"},
    {"Cream", "#fff4d6"},
    {"Amber", "#ffbf47"},
    {"Light green", "#a6e8a6"},
    {"Light blue", "#a8d8ff"},
    {"Light pink", "#ffb8d9"}
  ]

  @type message :: {:updated, DrawMusic.Accounts.User.t()}

  @doc "The preset dark-mode ink colors as `{name, \"#rrggbb\"}`."
  @spec presets() :: [{String.t(), String.t()}]
  def presets, do: @presets

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set", %{"color" => color}, socket) do
    case Accounts.update_user_preferences(socket.assigns.scope, %{score_ink_dark: color}) do
      {:ok, user} ->
        send(self(), {__MODULE__, {:updated, user}})
        {:noreply, assign(socket, :form, blank_form(%{socket.assigns.scope | user: user}))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :update}))}
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-3">
      <div class="flex flex-wrap gap-2 rounded-box bg-black p-3">
        <.swatch
          :for={{name, color} <- @presets}
          id={"#{@id}-#{String.trim_leading(color, "#")}"}
          name={name}
          color={color}
          chosen?={@current == color}
          target={@myself}
        />
      </div>
      <.custom_color id={"#{@id}-custom"} form={@form} current={@current} target={@myself} />
      <p
        :for={msg <- Enum.map(@form[:score_ink_dark].errors, &translate_error/1)}
        class="text-sm text-error"
      >
        {msg}
      </p>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{scope: %Scope{} = scope} = assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :scope]))
     |> assign(presets: @presets, current: scope.user.score_ink_dark || "#ffffff")
     |> assign_new(:form, fn -> blank_form(scope) end)}
  end

  def update(_assigns, _socket), do: raise(ArgumentError, "InkPicker needs a :scope")

  defp blank_form(scope) do
    scope
    |> Accounts.change_user_preferences()
    |> to_form()
  end

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :current, :string, required: true
  attr :target, :any, required: true

  defp custom_color(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@id}
      phx-submit="set"
      phx-target={@target}
      class="flex items-end gap-2"
    >
      <label class="flex flex-col gap-1 text-sm">
        Custom color
        <input
          type="color"
          name="color"
          value={@current}
          class="h-9 w-16 cursor-pointer rounded border border-base-300 bg-transparent"
        />
      </label>
      <button type="submit" class="btn btn-sm">Use color</button>
    </.form>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :color, :string, required: true
  attr :chosen?, :boolean, required: true
  attr :target, :any, required: true

  defp swatch(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      title={@name}
      aria-label={@name}
      aria-pressed={to_string(@chosen?)}
      phx-click="set"
      phx-value-color={@color}
      phx-target={@target}
      class={[
        "size-9 rounded-full border-2 transition-transform hover:scale-110 focus-visible:scale-110",
        if(@chosen?, do: "border-primary ring-2 ring-primary", else: "border-white/20")
      ]}
      style={"background-color: #{@color}"}
    />
    """
  end
end
