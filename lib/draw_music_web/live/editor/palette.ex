defmodule DrawMusicWeb.Editor.Palette do
  @moduledoc """
  The editor's toolbar, two rows tall, as a standalone LiveComponent: the
  Edit/Play switch, Edit mode's tools (`DrawMusicWeb.Palette.EditTools`),
  the `:play_controls` slot, help and the `:trailing` slot (save). It
  handles its buttons and its keyboard shortcuts (the colocated
  `.PaletteKeys` hook) and reports the results.

  The palette's state (what is armed, notes or rests, Insert or Overlay)
  is the editor's, because the score uses it too; the palette receives it,
  works out the next state with `DrawMusicWeb.EditorPalette`, and reports
  it. Playback isn't the palette's: the `:play_controls` slot is rendered
  in both modes, so what fills it (`DrawMusicWeb.Editor.Transport`) stays
  mounted and shows its controls in Play mode only.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:armed`, `:row_kind`, `:insert?`: the palette's state.
    * `:selection`: the selected ids, which the dot, the accidentals and
      the chords change when nothing is armed.
    * `:can_undo?`, `:can_redo?`, `:mode` (the key's), `:editor_mode`.
    * The `:below_mode`, `:play_controls` and `:trailing` slots, placed in
      the toolbar.

  ## Intents
    * `{:palette, changes}`: the palette's new state, what changed of
      `armed`, `row_kind` and `insert?`.
    * `{:edit, fun}`: the dot or an accidental on the selection.
    * `{:edit, fun, :select}`: a chord built on the selected notes.
    * `{:session, fun}`: select all.
    * `{:mode, mode}`: the Edit/Play buttons and P.
    * `{:history, :undo | :redo}`: the buttons and their keys.
    * `{:open, :settings}`: the settings button.
  """

  use DrawMusicWeb, :live_component

  import DrawMusicWeb.PaletteComponents
  import DrawMusicWeb.Palette.EditTools

  alias DrawMusic.Music.{Session, TempoEditing, Timeline}
  alias DrawMusicWeb.Editor.Intent
  alias DrawMusicWeb.{EditorCommands, EditorPalette}

  # What an input left out defaults to.
  @defaults %{
    armed: nil,
    row_kind: :note,
    insert?: false,
    selection: [],
    can_undo?: false,
    can_redo?: false,
    mode: :major,
    editor_mode: :edit,
    below_mode: [],
    play_controls: [],
    trailing: []
  }

  # Edit mode's events; in Play mode (its buttons gone, its keys off) a
  # stray one is ignored.
  @edit_events ~w(arm arm_value arm_chord arm_tie disarm single_notes toggle_rest toggle_dot
                  set_accidental toggle_insert select_all undo redo open_settings)

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(event, _params, %{assigns: %{editor_mode: :play}} = socket)
      when event in @edit_events do
    {:noreply, socket}
  end

  def handle_event("arm", %{"kind" => kind, "value" => value}, socket) do
    report_armed(EditorPalette.arm(socket.assigns.armed, kind, value))
    {:noreply, socket}
  end

  # The number keys arm a length of the row's kind, note or rest.
  def handle_event("arm_value", %{"value" => value}, socket) do
    %{armed: armed, row_kind: row_kind} = socket.assigns
    report_armed(EditorPalette.arm(armed, Atom.to_string(row_kind), value))
    {:noreply, socket}
  end

  # Chords don't apply to rests. With nothing armed and notes selected, a
  # chord turns the selected notes into that chord; otherwise it turns chord
  # mode on (or, picked again, off), whichever of length and chord came first.
  def handle_event("arm_chord", _params, %{assigns: %{row_kind: :rest}} = socket) do
    {:noreply, socket}
  end

  def handle_event("arm_chord", params, socket) do
    %{armed: armed, selection: selection} = socket.assigns

    case {EditorPalette.chord(params), armed, selection} do
      {:error, _armed, _selection} ->
        :ok

      {{:ok, chord}, nil, [_ | _] = ids} ->
        Intent.notify({:edit, EditorCommands.chordify(ids, chord), :select})

      {{:ok, chord}, armed, _selection} ->
        Intent.notify({:palette, %{armed: EditorPalette.arm_chord(armed, chord)}})
    end

    {:noreply, socket}
  end

  def handle_event("arm_tie", _params, socket) do
    Intent.notify({:palette, %{armed: EditorPalette.arm_tie()}})
    {:noreply, socket}
  end

  def handle_event("disarm", _params, socket) do
    Intent.notify({:palette, %{armed: nil}})
    {:noreply, socket}
  end

  def handle_event("open_settings", _params, socket) do
    Intent.notify({:open, :settings})
    {:noreply, socket}
  end

  def handle_event("redo", _params, socket) do
    Intent.notify({:history, :redo})
    {:noreply, socket}
  end

  # Every note and rest, on both staves, and every tempo change.
  def handle_event("select_all", _params, socket) do
    Intent.notify({:session, &Session.select(&1, all_ids(&1), false)})
    {:noreply, socket}
  end

  # With nothing armed, the accidentals change the selected notes.
  def handle_event("set_accidental", %{"alter" => name}, socket) do
    %{armed: armed, selection: selection} = socket.assigns

    case {EditorPalette.alter(name), armed} do
      {nil, _armed} ->
        :ok

      {alter, nil} ->
        Intent.notify({:edit, EditorCommands.set_alter(selection, alter)})

      {alter, armed} ->
        Intent.notify({:palette, %{armed: EditorPalette.set_accidental(armed, alter)}})
    end

    {:noreply, socket}
  end

  def handle_event("single_notes", _params, socket) do
    Intent.notify({:palette, %{armed: EditorPalette.single_notes(socket.assigns.armed)}})
    {:noreply, socket}
  end

  # With nothing armed, the dot changes the selection.
  def handle_event("toggle_dot", _params, %{assigns: %{armed: nil}} = socket) do
    Intent.notify({:edit, EditorCommands.toggle_dots(socket.assigns.selection)})
    {:noreply, socket}
  end

  def handle_event("toggle_dot", _params, socket) do
    Intent.notify({:palette, %{armed: EditorPalette.toggle_dot(socket.assigns.armed)}})
    {:noreply, socket}
  end

  def handle_event("toggle_insert", _params, socket) do
    Intent.notify({:palette, %{insert?: !socket.assigns.insert?}})
    {:noreply, socket}
  end

  def handle_event("toggle_mode", params, socket) do
    Intent.notify({:mode, next_mode(params["mode"], socket.assigns.editor_mode)})
    {:noreply, socket}
  end

  def handle_event("toggle_rest", _params, socket) do
    %{armed: armed, row_kind: row_kind} = socket.assigns
    {row_kind, armed} = EditorPalette.toggle_rest(row_kind, armed)
    Intent.notify({:palette, %{row_kind: row_kind, armed: armed}})
    {:noreply, socket}
  end

  def handle_event("undo", _params, socket) do
    Intent.notify({:history, :undo})
    {:noreply, socket}
  end

  # Anything else from the browser (malformed params) is ignored.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  # A two-row grid: the Edit/Play switch top left (Page and Strip, the
  # `:below_mode` slot, under it), help and save top right, and the current
  # mode's two rows of controls between them. Each row is a palette piece
  # tall (h-10) in both modes, so switching modes doesn't move the score.
  def render(assigns) do
    ~H"""
    <div
      id="palette"
      role="toolbar"
      aria-label="Palette"
      phx-hook=".PaletteKeys"
      phx-target={@myself}
      data-mode={@editor_mode}
      class="sticky top-0 z-20 grid grid-cols-[auto_auto_1fr_auto] grid-rows-[2.5rem_2.5rem] items-stretch gap-y-1 border-b border-base-300 bg-base-100/95 px-1 py-2 backdrop-blur"
    >
      <.mode_switch editor_mode={@editor_mode} target={@myself} />
      <div class="contents">
        {render_slot(@below_mode)}
      </div>
      <.edit_tools
        :if={@editor_mode == :edit}
        armed={@armed}
        row_kind={@row_kind}
        insert?={@insert?}
        can_undo?={@can_undo?}
        can_redo?={@can_redo?}
        mode={@mode}
        target={@myself}
      />
      {render_slot(@play_controls)}
      <div class="col-start-4 row-start-1 ml-3 flex items-stretch gap-1">
        <.help_button />
        {render_slot(@trailing)}
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PaletteKeys">
        // The palette's keyboard shortcuts, sent to the palette. P works in
        // both modes; the rest only in Edit (data-mode). The score's own
        // keys are the score hook's.
        import {dialogOpen, keyId, typing} from "@/js/score_editor/keyboard"

        const VALUES = ["whole", "half", "quarter", "eighth", "sixteenth", "thirty_second",
                        "sixty_fourth", "hundred_twenty_eighth", "two_hundred_fifty_sixth"]
        const EDIT_KEYS = {
          "Ctrl+Z": "undo",
          "Ctrl+Shift+Z": "redo",
          "Ctrl+Y": "redo",
          "Ctrl+A": "select_all",
          "Insert": "toggle_insert",
          "0": "disarm",
          "R": "toggle_rest",
          ".": "toggle_dot",
          "T": "arm_tie"
        }

        export default {
          mounted() {
            this.onKey = (e) => {
              this.key(e)
            }
            window.addEventListener("keydown", this.onKey)
          },
          destroyed() {
            window.removeEventListener("keydown", this.onKey)
          },
          key(e) {
            if (typing(e) || dialogOpen() || e.altKey) return
            const id = keyId(e)
            if (id === "P") return this.send(e, "toggle_mode")
            if (this.el.dataset.mode !== "edit") return
            if (/^[1-9]$/.test(id)) return this.send(e, "arm_value", {value: VALUES[Number(id) - 1]})
            if (EDIT_KEYS[id]) return this.send(e, EDIT_KEYS[id])
          },
          send(e, event, payload = {}) {
            e.preventDefault()
            this.pushEventTo(this.el, event, payload)
          }
        }
      </script>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    {:ok, assign(socket, Map.merge(@defaults, assigns))}
  end

  # Every note and rest and every tempo change in the session's score.
  defp all_ids(%Session{score: score, ctx: ctx}) do
    events = for entry <- Timeline.flatten(score, ctx), do: entry.event.id
    events ++ TempoEditing.ids(score)
  end

  defp next_mode("play", _current), do: :play
  defp next_mode("edit", _current), do: :edit
  defp next_mode(_toggle, :edit), do: :play
  defp next_mode(_toggle, :play), do: :edit

  defp report_armed({:ok, armed}), do: Intent.notify({:palette, %{armed: armed}})
  defp report_armed(:error), do: :ok
end
