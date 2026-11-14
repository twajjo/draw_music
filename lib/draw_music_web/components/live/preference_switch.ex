defmodule DrawMusicWeb.PreferenceSwitch do
  @moduledoc """
  An on/off switch for one of the user's yes-or-no preferences (e.g.
  `:name_notes`), saved as soon as it is flipped.

  A standalone LiveComponent: it saves the preference itself and works in
  any LiveView.

  ## Inputs
    * `:id` — the component's id; the checkbox's id is `"<id>-input"`.
    * `:scope` — the signed-in user's `DrawMusic.Accounts.Scope` (required).
    * `:field` — the preference, a boolean field of `DrawMusic.Accounts.User`
      that `User.preferences_changeset/2` accepts.
    * `:label` — what the switch is called; `:hint` — a line saying what it does.

  ## Messages to the parent
  Sent as `{DrawMusicWeb.PreferenceSwitch, message}`:
    * `{:updated, user}` — the preference is saved. The parent puts `user` in
      its scope.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Accounts
  alias DrawMusic.Accounts.Scope

  @type message :: {:updated, DrawMusic.Accounts.User.t()}

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("set", %{"value" => value}, socket) when value in ["true", "false"] do
    %{scope: scope, field: field} = socket.assigns

    case Accounts.update_user_preferences(scope, %{field => value == "true"}) do
      {:ok, user} -> send(self(), {__MODULE__, {:updated, user}})
      {:error, _changeset} -> :ignored
    end

    {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <form id={@id} phx-change="set" phx-target={@myself} class="space-y-1">
      <.input
        id={"#{@id}-input"}
        type="checkbox"
        name="value"
        value={Map.fetch!(@scope.user, @field)}
        label={@label}
        class="toggle toggle-primary"
      />
      <p class="text-sm opacity-70">{@hint}</p>
    </form>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{scope: %Scope{}, field: field} = assigns, socket) when is_atom(field) do
    {:ok, assign(socket, Map.take(assigns, [:id, :scope, :field, :label, :hint]))}
  end

  def update(_assigns, _socket) do
    raise ArgumentError, "PreferenceSwitch needs a :scope and a :field"
  end
end
