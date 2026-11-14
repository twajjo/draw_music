defmodule DrawMusicWeb.UserLive.Settings do
  use DrawMusicWeb, :live_view

  on_mount {DrawMusicWeb.UserAuth, :require_sudo_mode}

  alias DrawMusic.Accounts
  alias DrawMusicWeb.{InkPicker, LayoutToggle, PreferenceSwitch}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Preferences
          <:subtitle>
            Your account, and how the editor looks and helps you (a piece's own settings are in the editor)
          </:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div class="divider" />

      <section id="appearance" class="space-y-4">
        <.header>
          Appearance
          <:subtitle>
            Follow your system, or always use light or dark (saved in this browser)
          </:subtitle>
        </.header>
        <Layouts.theme_toggle />
      </section>

      <div class="divider" />

      <section id="score-display" class="space-y-4">
        <.header>
          Score display
          <:subtitle>How scores are laid out, and the notation color in dark mode</:subtitle>
        </.header>
        <div class="space-y-2">
          <p class="text-sm font-medium">Layout</p>
          <.live_component module={LayoutToggle} id="settings-layout" scope={@current_scope} />
        </div>
        <div class="space-y-2">
          <p class="text-sm font-medium">Dark mode ink</p>
          <.live_component module={InkPicker} id="settings-ink" scope={@current_scope} />
        </div>
      </section>

      <div class="divider" />

      <section id="reading-aids" class="space-y-4">
        <.header>
          Reading aids
          <:subtitle>Help with reading music, for when the notes aren't second nature yet</:subtitle>
        </.header>
        <.live_component
          module={PreferenceSwitch}
          id="settings-name-notes"
          scope={@current_scope}
          field={:name_notes}
          label="Name the note being placed or dragged"
          hint="Shows its name, like G♯4, beside the note while you place it or drag it"
        />
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  # A saved preference: the page (and its ink) follows the new user.
  @impl true
  def handle_info({component, {:updated, user}}, socket)
      when component in [InkPicker, LayoutToggle, PreferenceSwitch] do
    {:noreply, assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})}
  end

  # Anything else (e.g. the test mailer's copy of a sent email) is ignored,
  # as it was before this page handled any messages.
  def handle_info(_message, socket), do: {:noreply, socket}
end
