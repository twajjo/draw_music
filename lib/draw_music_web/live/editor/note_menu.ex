defmodule DrawMusicWeb.Editor.NoteMenu do
  @moduledoc """
  The right-click menu, at the pointer: for one note or rest (split, length,
  a third above or below, rest or note, ties, a tempo change there, delete),
  or for a selection (transpose, reverse, copy, cut, delete).

  A standalone LiveComponent: its actions are built by
  `DrawMusicWeb.EditorCommands.menu/4` and reported to the editor.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:menu`: the open `DrawMusicWeb.ContextMenu` (required).
    * `:score` and `:ctx`: the score, to start a tempo change in it (required).
    * `:insert?`: whether Insert mode is on (a longer length makes room).

  ## Intents
    * `{:edit, fun}`: an action on the score; then `:close`.
    * `{:session, fun}`: Copy (and Cut, before its edit) selects the menu's
      notes and copies them.
    * `{:open, {:tempo, target}}`: "Tempo change here…" opens the tempo
      dialog in the menu's place.
    * `{:flash, :error, message}`: a tempo change can't start there.
    * `:close`: Esc or a click outside.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Engraving.Smufl
  alias DrawMusic.Music.{Context, Score, Session}
  alias DrawMusicWeb.{ContextMenu, EditorCommands, EditorLive, TempoTarget}
  alias DrawMusicWeb.Editor.Intent

  # The actions `EditorCommands.menu/4` builds.
  @actions ~w(split set_value toggle_menu_dot to_rest to_note tie_next untie add_third_above
              add_third_below menu_delete transpose reverse)

  @intervals ~w(m2 M2 m3 M3 P4 A4 P5 m6 M6 m7 M7 P8)

  @lengths [
    {:whole, :noteWhole, "Whole"},
    {:half, :noteHalfUp, "Half"},
    {:quarter, :noteQuarterUp, "Quarter"},
    {:eighth, :note8thUp, "Eighth"},
    {:sixteenth, :note16thUp, "16th"},
    {:thirty_second, :note32ndUp, "32nd"},
    {:sixty_fourth, :note64thUp, "64th"},
    {:hundred_twenty_eighth, :note128thUp, "128th"},
    {:two_hundred_fifty_sixth, :note256thUp, "256th"}
  ]

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("close", _params, socket) do
    Intent.notify(:close)
    {:noreply, socket}
  end

  def handle_event("copy", _params, socket) do
    Intent.notify({:session, select_and_copy(socket.assigns.menu)})
    Intent.notify(:close)
    {:noreply, socket}
  end

  def handle_event("cut", _params, %{assigns: %{menu: menu}} = socket) do
    Intent.notify({:session, select_and_copy(menu)})
    Intent.notify({:edit, EditorCommands.delete(menu.ids, socket.assigns.insert?)})
    Intent.notify(:close)
    {:noreply, socket}
  end

  # "Tempo change here…": a new change where the note or rest starts, at
  # the tempo already in force there; its dialog takes the menu's place.
  def handle_event("tempo", _params, %{assigns: %{menu: menu}} = socket) do
    %{score: score, ctx: ctx} = socket.assigns

    case TempoTarget.at_event(score, ctx, menu.id) do
      {:ok, target} ->
        Intent.notify({:open, {:tempo, target}})

      {:error, :opening_beat} ->
        Intent.notify({:flash, :error, EditorLive.error_message(:opening_beat)})
        Intent.notify(:close)

      {:error, :not_found} ->
        Intent.notify(:close)
    end

    {:noreply, socket}
  end

  def handle_event(action, params, %{assigns: %{menu: menu}} = socket)
      when action in @actions do
    Intent.notify({:edit, EditorCommands.menu(action, params, menu, socket.assigns.insert?)})
    Intent.notify(:close)
    {:noreply, socket}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(%{menu: %ContextMenu{kind: :selection}} = assigns) do
    ~H"""
    <div>
      <.menu_box menu={@menu} width="w-64" target={@myself}>
        <p class="px-2 pb-1 text-xs opacity-60">{length(@menu.ids)} selected</p>
        <.transpose_items target={@myself} />
        <.separator />
        <.item id="menu-reverse" action="reverse" target={@myself}>Reverse</.item>
        <.item id="menu-copy" action="copy" target={@myself}>Copy</.item>
        <.item id="menu-cut" action="cut" target={@myself}>Cut</.item>
        <.separator />
        <.item id="menu-delete" action="menu_delete" target={@myself} danger>Delete</.item>
      </.menu_box>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <.menu_box menu={@menu} width="w-60" target={@myself}>
        <.item id="menu-split" action="split" target={@myself}>Split in two</.item>
        <.length_items target={@myself} />
        <.separator />
        <.note_items :if={@menu.kind == :note} target={@myself} />
        <.item :if={@menu.kind == :rest} id="menu-to-note" action="to_note" target={@myself}>
          Make it a note here
        </.item>
        <%!-- None on the opening beat: its tempo is the score's settings. --%>
        <.item :if={@menu.tempo?} id="menu-tempo" action="tempo" target={@myself}>
          Tempo change here…
        </.item>
        <.separator />
        <.item id="menu-delete" action="menu_delete" target={@myself} danger>Delete</.item>
      </.menu_box>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{menu: %ContextMenu{}, score: %Score{}, ctx: %Context{}} = assigns, socket) do
    {:ok, assign(socket, Map.put_new(assigns, :insert?, false))}
  end

  def update(_assigns, _socket) do
    raise ArgumentError, "NoteMenu needs a :menu, a :score and a :ctx"
  end

  # DOM ids must not differ only by case (m3 vs M3).
  defp interval_slug("m" <> n), do: "min" <> n
  defp interval_slug("M" <> n), do: "maj" <> n
  defp interval_slug("P" <> n), do: "p" <> n
  defp interval_slug("A" <> n), do: "aug" <> n

  attr :id, :string, required: true
  attr :action, :string, required: true
  attr :target, :any, required: true
  attr :danger, :boolean, default: false
  slot :inner_block, required: true

  defp item(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="menuitem"
      phx-click={@action}
      phx-target={@target}
      class={[
        "block w-full rounded px-2 py-1.5 text-left transition-colors hover:bg-base-200",
        @danger && "text-error"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :target, :any, required: true

  # The lengths a note or rest can take, and the dot. The browser sends a
  # button's own `value`.
  defp length_items(assigns) do
    assigns = assign(assigns, :lengths, @lengths)

    ~H"""
    <p class="px-2 pt-2 pb-1 text-xs opacity-60">Length</p>
    <div class="flex flex-wrap gap-1 px-1 pb-1">
      <button
        :for={{value, glyph, label} <- @lengths}
        id={"menu-length-#{value}"}
        type="button"
        title={label}
        aria-label={label}
        phx-click="set_value"
        phx-target={@target}
        value={value}
        class="grid h-8 w-7 place-items-center rounded transition-colors hover:bg-base-200"
      >
        <span class="font-['Bravura'] text-xl leading-none">{Smufl.char(glyph)}</span>
      </button>
      <button
        id="menu-length-dot"
        type="button"
        title="Dotted"
        aria-label="Dotted"
        phx-click="toggle_menu_dot"
        phx-target={@target}
        class="grid h-8 w-7 place-items-center rounded transition-colors hover:bg-base-200"
      >
        <span class="font-['Bravura'] text-xl leading-none">{Smufl.char(:augmentationDot)}</span>
      </button>
    </div>
    """
  end

  attr :menu, ContextMenu, required: true
  attr :width, :string, required: true
  attr :target, :any, required: true
  slot :inner_block, required: true

  # The menu's box at the pointer; Esc or a click outside closes it.
  defp menu_box(assigns) do
    ~H"""
    <div
      id="context-menu"
      role="menu"
      phx-click-away="close"
      phx-window-keydown="close"
      phx-key="Escape"
      phx-target={@target}
      class={[
        "fixed z-40 rounded-box border border-base-300 bg-base-100 p-2 text-sm shadow-xl",
        @width
      ]}
      style={"left: #{@menu.x}px; top: #{@menu.y}px"}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :target, :any, required: true

  # A note's own actions: chords, rest, ties.
  defp note_items(assigns) do
    ~H"""
    <.item id="menu-add-third-above" action="add_third_above" target={@target}>
      Add a 3rd above
    </.item>
    <.item id="menu-add-third-below" action="add_third_below" target={@target}>
      Add a 3rd below
    </.item>
    <.item id="menu-to-rest" action="to_rest" target={@target}>Make it a rest</.item>
    <.item id="menu-tie-next" action="tie_next" target={@target}>Tie to the next note</.item>
    <.item id="menu-untie" action="untie" target={@target}>Remove ties</.item>
    """
  end

  defp select_and_copy(%ContextMenu{ids: ids}) do
    fn session ->
      session
      |> Session.select(ids, false)
      |> Session.copy()
    end
  end

  defp separator(assigns) do
    ~H"""
    <div class="my-1 border-t border-base-300" />
    """
  end

  attr :target, :any, required: true

  # Up or down by a step, a semitone or an octave, or by any interval.
  defp transpose_items(assigns) do
    assigns = assign(assigns, :intervals, @intervals)

    ~H"""
    <p class="px-2 pt-1 pb-1 text-xs opacity-60">Transpose</p>
    <div class="grid grid-cols-2 gap-1 px-1">
      <%= for {by, label} <- [{"step", "Step"}, {"semitone", "Semitone"}, {"octave", "Octave"}],
              dir <- ["up", "down"] do %>
        <button
          id={"menu-transpose-#{by}-#{dir}"}
          type="button"
          phx-click="transpose"
          phx-value-by={by}
          phx-value-dir={dir}
          phx-target={@target}
          class="rounded px-2 py-1 text-left transition-colors hover:bg-base-200"
        >
          {label} {dir}
        </button>
      <% end %>
    </div>
    <details class="px-1 pt-1">
      <summary class="cursor-pointer rounded px-1 py-1 transition-colors hover:bg-base-200">
        By interval…
      </summary>
      <div class="grid grid-cols-4 gap-1 pt-1">
        <%= for interval <- @intervals, dir <- ["up", "down"] do %>
          <button
            id={"menu-interval-#{interval_slug(interval)}-#{dir}"}
            type="button"
            phx-click="transpose"
            phx-value-by="interval"
            phx-value-interval={interval}
            phx-value-dir={dir}
            phx-target={@target}
            class="rounded px-1 py-1 transition-colors hover:bg-base-200"
          >
            {interval} {if dir == "up", do: "↑", else: "↓"}
          </button>
        <% end %>
      </div>
    </details>
    """
  end
end
