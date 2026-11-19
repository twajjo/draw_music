defmodule DrawMusicWeb.Editor.ScoreCanvas do
  @moduledoc """
  The score on screen, as a standalone LiveComponent: the drawn score, the
  overlay the browser draws previews on, the bar controls, and the notes
  shown while it loads or is redrawn. Its browser side is the `.ScoreCanvas`
  hook (`DrawMusicWeb.ScoreCanvas.Surface`).

  It handles every event from the score: placing the armed item, dropping
  dragged notes, tying, the keys' edits (moving, deleting, copy, cut and
  paste), the bar controls, selecting (a click, a band and its preview),
  the tempo marks (opening, moving and resizing them), the right-click
  menu, Play mode's audition, disarming (Esc, a right-click while placing)
  and the opening marking's settings. A click on empty music puts the
  session's cursor there (drawn as a caret in Edit mode), for the next
  paste.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:session`: the `DrawMusic.Music.Session` (score, context, selection
      and clipboard).
    * `:engraved`: the laid-out score; `:pieces`: it drawn
      (`DrawMusicWeb.ScoreSvg.pieces/2`); `:geometry_json`: where things
      are, for the hook (`DrawMusicWeb.EditorGeometry.encode/2`).
    * `:armed`, `:insert?`: the palette's state.
    * `:editor_mode`: `:edit` or `:play`.
    * `:layout`: `:page` or `:strip`; `:loading?`: whether the score is
      still a placeholder; `:show_note_names?`: the user's preference.

  ## Intents
    * `{:session, fun}`: a new selection, the cursor put somewhere, or the
      selection copied.
    * `{:edit, fun}`: an edit (a tie, a key's edit, paste, a bar
      inserted, deleted or added).
    * `{:edit, fun, :follow}`: a placement; the cursor goes just after
      what was placed.
    * `{:edit, fun, :select}`: an edit whose notes end up selected (a drop,
      a tempo mark moved or resized).
    * `{:flash, :error, message}`: a placement the browser got wrong.
    * `{:open, {:menu, menu}}`: the right-click menu.
    * `{:open, {:tempo, target}}`: a tempo change's dialog.
    * `{:open, :settings}`: the score's settings, from the opening marking.
    * `{:palette, %{armed: nil}}`: disarm.

  Play mode's audition is pushed to the browser (`"audition"`), where the
  transport sounds it.
  """

  use DrawMusicWeb, :live_component

  import DrawMusicWeb.{EditorComponents, ScoreComponents}
  import DrawMusicWeb.ScoreCanvas.Surface

  alias DrawMusic.Music.{Editing, Playback, Session, TempoEditing, Timeline}

  alias DrawMusicWeb.{
    ContextMenu,
    EditorCommands,
    EditorGeometry,
    EditorPalette,
    EditorPlacement,
    PlaybackPayload,
    ScoreSvg,
    TempoTarget
  }

  alias DrawMusicWeb.Editor.{Intent, Messages}

  # Edit mode's events; Play mode ignores them.
  @edit_events ~w(add_measure cut delete delete_measure drop edit_tempo insert_measure move
                  move_tempo open_menu open_settings paste place resize_tempo tie)

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
          | {:reply, map(), Phoenix.LiveView.Socket.t()}
  def handle_event(event, _params, %{assigns: %{editor_mode: :play}} = socket)
      when event in @edit_events do
    {:noreply, socket}
  end

  def handle_event("add_measure", _params, socket) do
    Intent.notify({:edit, &Editing.append_measure/2})
    {:noreply, socket}
  end

  # Play mode: a click on a note sounds its chord (on Editor.Transport's
  # audio) and makes it the start point.
  def handle_event("audition", %{"id" => id}, %{assigns: %{editor_mode: :play}} = socket)
      when is_binary(id) do
    %{score: score, ctx: ctx} = socket.assigns.session

    case Playback.chord_at(score, ctx, id) do
      [] ->
        {:noreply, socket}

      events ->
        select([id])

        {:noreply,
         push_event(socket, "audition", %PlaybackPayload{
           events: events,
           span: Enum.max(Enum.map(events, & &1.duration)),
           loop: false
         })}
    end
  end

  def handle_event("clear_selection", _params, socket) do
    Intent.notify({:session, &Session.clear_selection/1})
    {:noreply, socket}
  end

  def handle_event("copy", _params, socket) do
    Intent.notify({:session, &Session.copy/1})
    {:noreply, socket}
  end

  def handle_event("cut", _params, socket) do
    Intent.notify({:session, &Session.copy/1})
    edit_selection(socket, &EditorCommands.delete(&1, socket.assigns.insert?))
    {:noreply, socket}
  end

  def handle_event("delete", _params, socket) do
    edit_selection(socket, &EditorCommands.delete(&1, socket.assigns.insert?))
    {:noreply, socket}
  end

  def handle_event("delete_measure", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index) do
      Intent.notify({:edit, &Editing.delete_measure(&1, &2, index)})
    end

    {:noreply, socket}
  end

  def handle_event("disarm", _params, socket) do
    Intent.notify({:palette, %{armed: nil}})
    {:noreply, socket}
  end

  def handle_event("drop", %{"ids" => ids, "steps" => steps} = params, socket)
      when is_list(ids) and is_integer(steps) do
    ids = Enum.filter(ids, &is_binary/1)
    Intent.notify({:edit, EditorCommands.drop(ids, steps, alter(params)), :select})
    {:noreply, socket}
  end

  # One note dragged on its own lands on whichever staff it was let go over.
  def handle_event("drop", %{"ids" => [id], "staff" => staff, "step" => step} = params, socket)
      when is_binary(id) and is_integer(step) do
    case EditorPlacement.staff(staff) do
      nil ->
        :ok

      staff ->
        Intent.notify(
          {:edit, EditorCommands.drop_on_staff(id, staff, step, alter(params)), :select}
        )
    end

    {:noreply, socket}
  end

  def handle_event("edit_tempo", %{"id" => id}, socket) when is_binary(id) do
    open_tempo_change(socket.assigns.session, id)
    {:noreply, socket}
  end

  def handle_event("insert_measure", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index) do
      Intent.notify({:edit, &Editing.insert_measure(&1, &2, index)})
    end

    {:noreply, socket}
  end

  # ↑/↓ by scale step (Shift: octave, Ctrl: semitone); ←/→ by beat.
  def handle_event("move", %{"dir" => dir}, socket) when dir in ~w(left right) do
    edit_selection(socket, fn ids -> &Editing.shift(&1, &2, ids, beats(dir)) end)
    {:noreply, socket}
  end

  def handle_event("move", %{"dir" => dir} = params, socket) when dir in ~w(up down) do
    edit_selection(socket, &EditorCommands.transpose(&1, params["by"] || "step", dir))
    {:noreply, socket}
  end

  def handle_event("move_tempo", %{"id" => id, "tick" => tick}, socket)
      when is_binary(id) and is_integer(tick) do
    Intent.notify({:edit, &with_ids(TempoEditing.move(&1, &2, id, tick), [id]), :select})
    {:noreply, socket}
  end

  # A right-click anywhere in the music. The selection decides which menu
  # opens (`ContextMenu.subject/2`); `id` is what was under the pointer.
  def handle_event("open_menu", %{"x" => x, "y" => y} = params, socket)
      when is_number(x) and is_number(y) do
    %{session: session} = socket.assigns

    case ContextMenu.subject(session.selection, clicked_id(params)) do
      :none -> :ok
      {:selection, ids} -> Intent.notify({:open, {:menu, ContextMenu.for_selection(ids, params)}})
      {:event, id} -> open_event_menu(session, id, params)
    end

    {:noreply, socket}
  end

  def handle_event("open_settings", _params, socket) do
    Intent.notify({:open, :settings})
    {:noreply, socket}
  end

  # At the tick the browser gives, else where the selection starts, else at
  # the cursor (see `Session.paste_at/2`): ahead of the selection in Insert,
  # over it in Overlay. The cursor then follows the pasted music.
  def handle_event(
        "paste",
        params,
        %{assigns: %{session: %{clipboard: %{} = clipboard}}} = socket
      ) do
    %{session: session, insert?: insert?} = socket.assigns
    at = Session.paste_at(session, params["at"])
    paste = EditorCommands.paste(clipboard, at, insert?, Session.selection_ids(session))
    Intent.notify({:edit, paste, :follow})
    {:noreply, socket}
  end

  # The armed item stays armed after a placement, until another is picked
  # or it's disarmed. (A press on a note or rest itself selects it: the
  # hook sends `select`.)
  def handle_event("place", params, %{assigns: %{armed: %{} = armed}} = socket) do
    insert? = socket.assigns.insert?

    case EditorPlacement.parse(params) do
      {:ok, target} ->
        Intent.notify({:edit, &EditorPlacement.place(&1, &2, armed, target, insert?), :follow})

      :error ->
        Intent.notify({:flash, :error, Messages.refused(:invalid)})
    end

    {:noreply, socket}
  end

  # While a band is dragged: what letting go would select, for the hook to
  # light up. Nothing changes until it does.
  def handle_event("preview_range", %{"from" => from, "to" => to}, socket)
      when is_integer(from) and is_integer(to) do
    {:reply, %{ids: range_ids(socket.assigns.session, from, to)}, socket}
  end

  def handle_event("resize_tempo", %{"id" => id, "tick" => tick}, socket)
      when is_binary(id) and is_integer(tick) do
    Intent.notify({:edit, &with_ids(TempoEditing.resize(&1, &2, id, tick), [id]), :select})
    {:noreply, socket}
  end

  def handle_event("select", %{"ids" => [id], "add" => true}, socket) when is_binary(id) do
    Intent.notify({:session, &Session.toggle(&1, id)})
    {:noreply, socket}
  end

  def handle_event("select", %{"ids" => ids} = params, socket) when is_list(ids) do
    ids = Enum.filter(ids, &is_binary/1)
    add? = params["add"] == true

    Intent.notify({:session, &Session.select(&1, ids, add?)})
    {:noreply, socket}
  end

  def handle_event("select_range", %{"from" => from, "to" => to}, socket)
      when is_integer(from) and is_integer(to) do
    select(range_ids(socket.assigns.session, from, to))
    {:noreply, socket}
  end

  # A click on empty music puts the cursor there: where the next paste goes.
  # Ctrl+Home and Ctrl+End send it too, at the start and the end.
  def handle_event("set_cursor", %{"at" => at}, socket) when is_integer(at) and at >= 0 do
    Intent.notify({:session, &Session.put_cursor(&1, at)})
    {:noreply, socket}
  end

  def handle_event("tie", %{"from" => from, "to" => to}, socket)
      when is_binary(from) and is_binary(to) do
    Intent.notify({:edit, &Editing.tie(&1, &2, from, to)})
    {:noreply, socket}
  end

  # Events that don't fit the current state (malformed params, a stray
  # audition in Edit mode, paste with nothing copied, a placement with
  # nothing armed) are ignored rather than crashing the editor.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="score-canvas" class="contents">
      <.loading_note />
      <.redrawing_note />
      <.surface
        target={@myself}
        geometry_json={@geometry_json}
        armed_json={Jason.encode!(EditorGeometry.armed(@armed, @session.ctx))}
        insert?={@insert?}
        editor_mode={@editor_mode}
        loading?={@loading?}
        layout={@layout}
        show_note_names?={@show_note_names?}
        cursor={@session.cursor}
        selected?={MapSet.size(@session.selection) > 0}
      >
        <.score
          id="score"
          layout={@engraved}
          pieces={ScoreSvg.select(@pieces, @session.selection)}
          strip?={@layout == :strip}
        />
        <%!-- The hook draws the cursor glyph and previews here. --%>
        <svg
          id="score-overlay"
          phx-update="ignore"
          xmlns="http://www.w3.org/2000/svg"
          class="pointer-events-none absolute inset-0 h-full w-full"
          style="color: var(--score-ink)"
        />
        <.measure_controls
          :if={@editor_mode == :edit}
          engraved={@engraved}
          score={@session.score}
          target={@myself}
        />
      </.surface>
    </div>
    """
  end

  # The palette's alteration of a dropped note, if a modifier was held.
  defp alter(params), do: EditorPalette.alter(to_string(params["alter"]))

  defp beats("left"), do: -1
  defp beats("right"), do: 1

  # What was under a right-click; the browser sends none off the notes.
  defp clicked_id(%{"id" => id}) when is_binary(id), do: id
  defp clicked_id(_params), do: nil

  # Edits the selection with the edit `command.(ids)` makes; with nothing
  # selected there is nothing to do.
  defp edit_selection(%{assigns: %{session: session}}, command) do
    case Session.selection_ids(session) do
      [] -> :ok
      ids -> Intent.notify({:edit, command.(ids)})
    end
  end

  defp loading_note(assigns) do
    ~H"""
    <%!-- Shown until the score has arrived and the browser has drawn it:
         the hook hides it (data-loading says whether it has arrived). --%>
    <p
      id="score-loading"
      phx-update="ignore"
      class="flex items-center gap-2 pb-2 text-sm"
      style="color: var(--score-ink)"
    >
      <span class="loading loading-spinner loading-sm" />
      <span id="score-loading-text">Loading the score…</span>
    </p>
    """
  end

  # A note or rest gets its own menu; a tempo mark opens its dialog.
  defp open_event_menu(%Session{score: score, ctx: ctx} = session, id, params) do
    case Session.find_event(session, id) do
      nil ->
        open_tempo_change(session, id)

      event ->
        start = Timeline.start_of(score, ctx, id)
        menu = %{ContextMenu.for_event(event, params) | tempo?: TempoEditing.changeable?(start)}
        Intent.notify({:open, {:menu, menu}})
    end
  end

  # The tempo dialog for an existing change, which becomes the selection.
  defp open_tempo_change(%Session{score: score, ctx: ctx}, id) do
    case TempoEditing.find(score, id) do
      {:ok, change} ->
        select([id])
        Intent.notify({:open, {:tempo, TempoTarget.for_change(score, ctx, change)}})

      {:error, _not_found} ->
        :ok
    end
  end

  defp parse_index(index) do
    case Integer.parse(to_string(index)) do
      {index, ""} -> {:ok, index}
      _ -> :error
    end
  end

  # The notes and rests between two ticks, in either order.
  defp range_ids(%Session{score: score, ctx: ctx}, from, to) do
    Editing.select_range(score, ctx, min(from, to), max(from, to))
  end

  defp redrawing_note(assigns) do
    ~H"""
    <%!-- Shown by the hook from a change of layout until the browser has
         drawn the score in the new one; it floats so it's seen wherever
         the page is scrolled. --%>
    <p
      id="score-redrawing"
      phx-update="ignore"
      hidden
      role="status"
      class="fixed inset-x-0 top-1/3 z-40 mx-auto flex w-fit items-center gap-2 rounded-full border border-base-300 bg-base-100 px-4 py-2 text-sm shadow-lg"
    >
      <span class="loading loading-spinner loading-sm" /> Redrawing the music…
    </p>
    """
  end

  # Selects just `ids`.
  defp select(ids), do: Intent.notify({:session, &Session.select(&1, ids, false)})

  defp with_ids({:ok, score}, ids), do: {:ok, score, ids}
  defp with_ids(error, _ids), do: error
end
