defmodule DrawMusicWeb.PreferencesForm do
  @moduledoc """
  The user's preferences as one form: the application's theme, the score's
  layout and dark-mode ink, and the reading aids. Nothing is stored until
  **Save**.

  While it's open, each valid change is previewed: the parent is sent the
  user with the changes applied (not stored), so the page behind shows them.
  **Cancel** goes back to the stored preferences; **Defaults** fills the form
  with a new user's values, previewed but not stored until Save. An ink too
  dark to read on black shows its error and isn't previewed or saved.

  The theme is kept in the browser, not with the user: its field
  (`DrawMusicWeb.ThemeChoice`) previews itself, and the form tells it when to
  store (Save) or go back to "system" (Defaults).

  A standalone LiveComponent: it keeps the form and the stored preferences
  (as they were when it opened) to itself, and works in any LiveView.

  ## Inputs
    * `:id`: the component's id (the form's too).
    * `:scope`: the signed-in user's `DrawMusic.Accounts.Scope`. Its user when
      the form opens is the stored one; later scopes (the previews coming back)
      don't change that.

  ## Messages to the parent
  Sent as `{DrawMusicWeb.PreferencesForm, message}`:
    * `{:preview, user}`: the preferences as the form has them, not stored.
    * `{:saved, user}`: stored; the parent closes or leaves the form.
    * `{:cancelled, user}`: the stored preferences, for the parent to go back
      to; it closes or leaves the form.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Accounts
  alias DrawMusic.Accounts.{Scope, User}
  alias DrawMusicWeb.ThemeChoice

  @fields [
    :score_layout,
    :score_ink_dark,
    :show_note_names,
    :note_names_in_edit_only,
    :letter_staves
  ]

  @presets [
    {"White", "#ffffff"},
    {"Cream", "#fff4d6"},
    {"Amber", "#ffbf47"},
    {"Light green", "#a6e8a6"},
    {"Light blue", "#a8d8ff"},
    {"Light pink", "#ffb8d9"}
  ]

  @layouts [
    {:page, "Page", "Rows, like sheet music"},
    {:strip, "Strip", "One long staff"}
  ]

  @type message ::
          {:preview, User.t()} | {:saved, User.t()} | {:cancelled, User.t()}

  @doc "The preset dark-mode ink colors as `{name, \"#rrggbb\"}`."
  @spec presets() :: [{String.t(), String.t()}]
  def presets, do: @presets

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("cancel", _params, socket) do
    notify({:cancelled, socket.assigns.stored})
    {:noreply, socket}
  end

  # A change of any field; the custom color picker sets the ink.
  def handle_event("change", params, socket) do
    changes =
      params
      |> Map.get("user", %{})
      |> custom_ink(params["custom_ink"], ink(socket.assigns.draft))

    {:noreply, change(socket, Map.merge(socket.assigns.params, changes))}
  end

  def handle_event("defaults", _params, socket) do
    socket =
      socket
      |> change(defaults())
      |> push_event("theme:default", %{})

    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    %{stored: stored, params: params} = socket.assigns

    case Accounts.update_user_preferences(Scope.for_user(stored), params) do
      {:ok, user} ->
        notify({:saved, user})
        {:noreply, push_event(socket, "theme:save", %{})}

      {:error, changeset} ->
        {:noreply, assign_form(socket, %{changeset | action: :update})}
    end
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div>
      <.form for={@form} id={@id} phx-change="change" phx-submit="save" phx-target={@myself}>
        <div class="space-y-8">
          <ThemeChoice.theme_choice id={"#{@id}-theme"} />
          <div class="divider" />
          <.score_display id={@id} form={@form} draft={@draft} />
          <div class="divider" />
          <.reading_aids id={@id} form={@form} draft={@draft} />
          <.actions id={@id} target={@myself} valid?={@form.source.valid?} />
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{scope: %Scope{user: %User{} = user}} = assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign_new(:stored, fn -> user end)

    {:ok, if(socket.assigns[:form], do: socket, else: change(socket, %{}))}
  end

  def update(_assigns, _socket), do: raise(ArgumentError, "PreferencesForm needs a :scope")

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :valid?, :boolean, required: true

  defp actions(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-2 border-t border-base-300 pt-4">
      <button
        id={"#{@id}-defaults"}
        type="button"
        phx-click="defaults"
        phx-target={@target}
        class="btn btn-ghost btn-sm"
      >
        Defaults
      </button>
      <div class="flex gap-2">
        <button
          id={"#{@id}-cancel"}
          type="button"
          phx-click="cancel"
          phx-target={@target}
          class="btn btn-sm"
        >
          Cancel
        </button>
        <button id={"#{@id}-save"} type="submit" class="btn btn-primary btn-sm" disabled={not @valid?}>
          Save
        </button>
      </div>
    </div>
    """
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  # The form at `params` (the changes so far) over the stored preferences,
  # previewed when valid and different from the last preview.
  defp change(socket, params) do
    changeset = User.preferences_changeset(socket.assigns.stored, params)
    draft = Ecto.Changeset.apply_changes(changeset)

    if changeset.valid? and draft != socket.assigns[:draft], do: notify({:preview, draft})

    socket
    |> assign(:params, params)
    |> assign(:draft, if(changeset.valid?, do: draft, else: socket.assigns[:draft] || draft))
    |> assign_form(%{changeset | action: :validate})
  end

  # The color picker always shows the current ink; a different color in it
  # is a custom pick, which beats the swatches.
  defp custom_ink(changes, nil = _picked, _current), do: changes
  defp custom_ink(changes, current, current), do: changes
  defp custom_ink(changes, picked, _current), do: Map.put(changes, "score_ink_dark", picked)

  # A new user's preferences, as form params.
  defp defaults do
    user = %User{}
    Map.new(@fields, fn field -> {Atom.to_string(field), param(Map.fetch!(user, field))} end)
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :color, :string, required: true
  attr :chosen?, :boolean, required: true
  attr :field_name, :string, required: true

  defp ink_swatch(assigns) do
    ~H"""
    <label
      id={@id}
      title={@name}
      class={[
        "size-9 cursor-pointer rounded-full border-2 transition-transform hover:scale-110 has-[:focus-visible]:scale-110",
        if(@chosen?, do: "border-primary ring-2 ring-primary", else: "border-white/20")
      ]}
      style={"background-color: #{@color}"}
    >
      <input
        type="radio"
        name={@field_name}
        value={@color}
        checked={@chosen?}
        aria-label={@name}
        class="sr-only"
      />
    </label>
    """
  end

  # The ink as shown: no ink (nil) is white.
  defp ink(%User{score_ink_dark: nil}), do: "#ffffff"
  defp ink(%User{score_ink_dark: color}), do: color

  attr :id, :string, required: true
  attr :layout, :atom, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true
  attr :current, :atom, required: true
  attr :field_name, :string, required: true

  # Picking a different layout first tells a score on the page that it's
  # being redrawn (`"score:redraw"`), as the server lays it out again.
  defp layout_choice(assigns) do
    ~H"""
    <label
      id={@id}
      title={@hint}
      phx-click={@current != @layout && JS.dispatch("score:redraw", detail: %{layout: @layout})}
      class={[
        "join-item btn btn-sm transition-colors",
        if(@current == @layout, do: "btn-primary", else: "btn-ghost")
      ]}
    >
      <input
        type="radio"
        name={@field_name}
        value={@layout}
        checked={@current == @layout}
        class="sr-only"
      />
      {@label}
    </label>
    """
  end

  defp notify(message), do: send(self(), {__MODULE__, message})

  defp param(nil), do: ""
  defp param(value), do: to_string(value)

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :draft, User, required: true

  defp reading_aids(assigns) do
    ~H"""
    <section id="reading-aids" class="space-y-4">
      <.header>
        Reading aids
        <:subtitle>Help with reading music, for when the notes aren't second nature yet</:subtitle>
      </.header>
      <.switch
        field={@form[:show_note_names]}
        id={"#{@id}-show-note-names"}
        label="Show note names"
        hint="Shows a note's name, like G♯, beside it, with ♮ where a natural sign is written. Never in downloads"
      />
      <.switch
        field={@form[:note_names_in_edit_only]}
        id={"#{@id}-note-names-in-edit-only"}
        disabled={not @draft.show_note_names}
        label="Only while editing and placing"
        hint="On: names show while you place a note, drag it or have it selected (a range too). Off: every note is named at all times. Needs note names shown"
      />
      <.switch
        field={@form[:letter_staves]}
        id={"#{@id}-letter-staves"}
        label="Letter the staff lines and spaces"
        hint="Tiny letters at the start of each line of music: E G B D F and F A C E on the treble staff, G B D F A and A C E G on the bass, and middle C. Never in downloads"
      />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :draft, User, required: true

  defp score_display(assigns) do
    assigns =
      assign(assigns,
        presets: @presets,
        layouts: @layouts,
        ink: ink(assigns.draft)
      )

    ~H"""
    <section id="score-display" class="space-y-4">
      <.header>
        Score display
        <:subtitle>How scores are laid out, and the notation color in dark mode</:subtitle>
      </.header>
      <div class="space-y-2">
        <p class="text-sm font-medium">Layout</p>
        <div id={"#{@id}-layout"} class="join" role="radiogroup" aria-label="Score layout">
          <.layout_choice
            :for={{layout, label, hint} <- @layouts}
            id={"#{@id}-layout-#{layout}"}
            layout={layout}
            label={label}
            hint={hint}
            current={@draft.score_layout}
            field_name={@form[:score_layout].name}
          />
        </div>
      </div>
      <div id={"#{@id}-ink"} class="space-y-3">
        <p class="text-sm font-medium">Dark mode ink</p>
        <div class="flex flex-wrap gap-2 rounded-box bg-black p-3" role="radiogroup">
          <.ink_swatch
            :for={{name, color} <- @presets}
            id={"#{@id}-ink-#{String.trim_leading(color, "#")}"}
            name={name}
            color={color}
            chosen?={@ink == color}
            field_name={@form[:score_ink_dark].name}
          />
        </div>
        <label class="flex items-center gap-2 text-sm">
          Custom color
          <input
            id={"#{@id}-ink-custom"}
            type="color"
            name="custom_ink"
            value={@ink}
            class="h-9 w-16 cursor-pointer rounded border border-base-300 bg-transparent"
          />
        </label>
        <p
          :for={msg <- Enum.map(@form[:score_ink_dark].errors, &translate_error/1)}
          class="text-sm text-error"
        >
          {msg}
        </p>
      </div>
    </section>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true
  attr :disabled, :boolean, default: false

  defp switch(assigns) do
    ~H"""
    <div class="space-y-1">
      <.input
        field={@field}
        id={@id}
        type="checkbox"
        label={@label}
        disabled={@disabled}
        class="toggle toggle-primary"
      />
      <p class="text-sm opacity-70">{@hint}</p>
    </div>
    """
  end
end
