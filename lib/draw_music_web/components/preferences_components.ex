defmodule DrawMusicWeb.PreferencesComponents do
  @moduledoc """
  The user's preferences (appearance, score display, reading aids), drawn on
  the Preferences page and in the editor's Preferences panel alike.

  Each preference saves itself (`LayoutToggle`, `InkPicker`,
  `PreferenceSwitch`) and tells the LiveView with `{module, {:updated, user}}`.
  The panel is opened and closed by a URL patch, so the editor behind it
  stays as it was, unsaved changes included.
  """

  use DrawMusicWeb, :html

  alias DrawMusicWeb.{InkPicker, LayoutToggle, PreferenceSwitch}

  @doc "Light, dark or the system's theme (kept in this browser)."
  @spec appearance(map()) :: Phoenix.LiveView.Rendered.t()
  def appearance(assigns) do
    ~H"""
    <section id="appearance" class="space-y-4">
      <.header>
        Appearance
        <:subtitle>Follow your system, or always use light or dark (saved in this browser)</:subtitle>
      </.header>
      <Layouts.theme_toggle />
    </section>
    """
  end

  @doc "All the preference sections, one under the other."
  attr :scope, :map, required: true

  @spec preference_sections(map()) :: Phoenix.LiveView.Rendered.t()
  def preference_sections(assigns) do
    ~H"""
    <.appearance />
    <div class="divider" />
    <.score_display scope={@scope} />
    <div class="divider" />
    <.reading_aids scope={@scope} />
    """
  end

  @doc """
  The preferences over the editor. `close` is the editor's own address: the
  close button, Esc and a click outside patch back to it. The patches replace
  the history entry rather than add one, so Back still leaves the editor
  (asking first about unsaved changes).
  """
  attr :scope, :map, required: true
  attr :close, :string, required: true

  @spec preferences_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def preferences_panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        id="preferences-panel"
        role="dialog"
        aria-label="Preferences"
        class="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away={JS.patch(@close, replace: true)}
        phx-window-keydown={JS.patch(@close, replace: true)}
        phx-key="Escape"
      >
        <div class="flex items-center justify-between gap-4">
          <h2 class="text-lg font-semibold">Preferences</h2>
          <.link
            id="preferences-close"
            patch={@close}
            replace
            class="btn btn-ghost btn-sm"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.link>
        </div>
        <div class="mt-4">
          <.preference_sections scope={@scope} />
        </div>
      </div>
    </div>
    """
  end

  @doc "Help with reading music, for novices."
  attr :scope, :map, required: true

  @spec reading_aids(map()) :: Phoenix.LiveView.Rendered.t()
  def reading_aids(assigns) do
    ~H"""
    <section id="reading-aids" class="space-y-4">
      <.header>
        Reading aids
        <:subtitle>Help with reading music, for when the notes aren't second nature yet</:subtitle>
      </.header>
      <.live_component
        module={PreferenceSwitch}
        id="settings-name-notes"
        scope={@scope}
        field={:name_notes}
        label="Name the note being placed or moved"
        hint="Shows its name, like G♯, beside the note while you place it, drag it or move it with ↑/↓"
      />
      <.live_component
        module={PreferenceSwitch}
        id="settings-letter-staves"
        scope={@scope}
        field={:letter_staves}
        label="Letter the staff lines and spaces"
        hint="Tiny letters at the start of each line of music: E G B D F and F A C E on the treble staff, G B D F A and A C E G on the bass, and middle C. Never in downloads"
      />
    </section>
    """
  end

  @doc "How scores are laid out, and the notation's color in dark mode."
  attr :scope, :map, required: true

  @spec score_display(map()) :: Phoenix.LiveView.Rendered.t()
  def score_display(assigns) do
    ~H"""
    <section id="score-display" class="space-y-4">
      <.header>
        Score display
        <:subtitle>How scores are laid out, and the notation color in dark mode</:subtitle>
      </.header>
      <div class="space-y-2">
        <p class="text-sm font-medium">Layout</p>
        <.live_component module={LayoutToggle} id="settings-layout" scope={@scope} />
      </div>
      <div class="space-y-2">
        <p class="text-sm font-medium">Dark mode ink</p>
        <.live_component module={InkPicker} id="settings-ink" scope={@scope} />
      </div>
    </section>
    """
  end
end
