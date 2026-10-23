defmodule DrawMusicWeb.EditorLive do
  @moduledoc """
  The score editor, in the user's preferred layout (one long staff or
  page-style systems). `:show` opens a saved version; `:new` (the main
  page) starts a blank, unsaved composition: C major, 4/4, four empty
  measures.

  The score lives in a `DrawMusic.Music.Session` (selection, clipboard,
  undo/redo, unsaved changes); the palette state (armed item, note/rest
  row, Insert mode) is kept beside it. Every change goes through
  `apply_edit/2`; the edits themselves are built by
  `DrawMusicWeb.EditorCommands` and `DrawMusicWeb.EditorPlacement`.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.{
    EditorComponents,
    LibraryComponents,
    PaletteComponents,
    ScoreComponents,
    SettingsComponents
  }

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.{Context, Editing, Note, Playback, Score, Session, Timeline, Transpose}

  alias DrawMusicWeb.{
    ContextMenu,
    EditorCommands,
    EditorGeometry,
    EditorPalette,
    EditorPlacement,
    EditorSettings,
    InstrumentSource,
    PlaybackPayload,
    ScorePreferences,
    VersionLookup
  }

  @draft_measures 4
  @menu_events ~w(split set_value toggle_menu_dot to_rest to_note tie_next untie menu_delete transpose reverse)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <header class="flex flex-wrap items-end justify-between gap-4">
        <div class="space-y-1">
          <h1 id="composition-name" class="text-2xl font-semibold">{@composition.name}</h1>
          <p :if={@composition.subtitle} class="opacity-80">{@composition.subtitle}</p>
          <p :if={credits(@composition) != ""} class="text-sm opacity-60">{credits(@composition)}</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <%= if @version.id do %>
            <.version_picker id="version-picker" composition={@composition} version={@version} />
          <% else %>
            <span id="unsaved" class="badge badge-ghost">Unsaved</span>
          <% end %>
          <.layout_toggle id="score-layout" layout={@current_scope.user.score_layout} />
          <.button
            :if={@version.id}
            id="download-svg"
            href={export_path(@version, "svg")}
            download
            class="btn btn-sm"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> SVG
          </.button>
          <.button
            :if={@version.id}
            id="download-mid"
            href={export_path(@version, "mid")}
            download
            class="btn btn-sm"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> MIDI
          </.button>
        </div>
      </header>

      <.palette
        armed={@armed}
        row_kind={@row_kind}
        insert?={@insert?}
        can_undo?={@session.undo != []}
        can_redo?={@session.redo != []}
        mode={@session.ctx.mode}
        playing?={@playing?}
      >
        <:trailing>
          <.save_menu dirty?={@session.dirty?} saved?={@version.id != nil} />
        </:trailing>
      </.palette>

      <div
        id="score-paper"
        class={[
          "rounded-box border border-base-300 p-4 shadow-sm transition-colors",
          if(@current_scope.user.score_layout == :strip, do: "overflow-x-auto")
        ]}
        style="background-color: var(--score-paper)"
      >
        <div
          id="score-editor"
          phx-hook="ScoreEditor"
          class={[
            "relative",
            if(@current_scope.user.score_layout == :page,
              do: "mx-auto w-full max-w-5xl",
              else: "w-fit"
            )
          ]}
          data-geometry={Jason.encode!(EditorGeometry.encode(@engraved, @session.ctx))}
          data-armed={Jason.encode!(EditorGeometry.armed(@armed))}
          data-dirty={to_string(@session.dirty?)}
          data-instrument={Jason.encode!(@instrument_source)}
        >
          <.score
            id="score"
            layout={@engraved}
            selection={@session.selection}
            class={["block", @current_scope.user.score_layout == :page && "h-auto w-full"]}
          />
          <%!-- The hook draws the cursor glyph and previews here. --%>
          <svg
            id="score-overlay"
            phx-update="ignore"
            xmlns="http://www.w3.org/2000/svg"
            class="pointer-events-none absolute inset-0 h-full w-full"
            style="color: var(--score-ink)"
          />
          <.measure_controls engraved={@engraved} score={@session.score} />
        </div>
        <.context_menu :if={@menu} menu={@menu} />
        <.save_as_dialog :if={@save_as_form} form={@save_as_form} />
        <.settings_panel :if={@settings_form} form={@settings_form} />
        <.transpose_dialog
          :if={@pending_key}
          key_name={Key.name(elem(@pending_key, 0), elem(@pending_key, 1))}
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {composition, version, title} =
      load(socket.assigns.live_action, socket.assigns.current_scope, params)

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:composition, composition)
     |> assign(:version, version)
     |> assign(:session, Session.new(version.score, Context.from_version(version)))
     |> assign(armed: nil, row_kind: :note, insert?: false, last_click: nil, menu: nil)
     |> assign(save_as_form: nil, settings_form: nil, pending_key: nil, playing?: false)
     # The tempo marking and instrument aren't part of the score's Context;
     # they're saved beside it.
     |> assign(:tempo_text, version.tempo_text)
     |> assign_instrument(version.instrument)
     |> assign_layout()}
  end

  defp load(:new, _scope, _params) do
    composition = %Composition{name: "Untitled", keys: []}
    key = %Key{sf: 0, mode: :major, composition: composition}
    {composition, %Version{key: key, score: Score.new(@draft_measures)}, "Untitled"}
  end

  defp load(:show, scope, params) do
    version = VersionLookup.fetch!(scope, params)
    composition = Library.get_composition!(scope, version.key.composition.id)
    {composition, version, "#{composition.name} · #{Key.name(version.key)} v#{version.number}"}
  end

  ## Palette

  @impl true
  def handle_event("arm", %{"kind" => kind, "value" => value}, socket) do
    {:noreply, arm(socket, EditorPalette.arm(socket.assigns.armed, kind, value))}
  end

  def handle_event("lock", %{"kind" => kind, "value" => value}, socket) do
    {:noreply, arm(socket, EditorPalette.arm(socket.assigns.armed, kind, value, true))}
  end

  def handle_event("arm_value", %{"value" => value}, socket) do
    kind = Atom.to_string(socket.assigns.row_kind)
    {:noreply, arm(socket, EditorPalette.arm(socket.assigns.armed, kind, value))}
  end

  def handle_event("arm_chord", params, socket) do
    {:noreply, arm(socket, EditorPalette.arm_chord(socket.assigns.armed, params))}
  end

  def handle_event("arm_tie", _params, socket) do
    {:noreply, assign(socket, :armed, EditorPalette.arm_tie())}
  end

  def handle_event("disarm", _params, socket), do: {:noreply, assign(socket, :armed, nil)}

  def handle_event("toggle_rest", _params, socket) do
    {row_kind, armed} = EditorPalette.toggle_rest(socket.assigns.row_kind, socket.assigns.armed)
    {:noreply, assign(socket, row_kind: row_kind, armed: armed)}
  end

  # With nothing armed, the dot and accidental buttons change the selection.
  def handle_event("toggle_dot", _params, %{assigns: %{armed: nil}} = socket) do
    events = selected_events(socket.assigns.session)
    dots = if Enum.all?(events, &(&1.dots > 0)), do: 0, else: 1
    ids = Enum.map(events, & &1.id)
    {:noreply, edit(socket, &Editing.set_dots(&1, &2, ids, dots))}
  end

  def handle_event("toggle_dot", _params, socket) do
    {:noreply, assign(socket, :armed, EditorPalette.toggle_dot(socket.assigns.armed))}
  end

  def handle_event("set_accidental", %{"alter" => name}, socket) do
    case {EditorPalette.alter(name), socket.assigns.armed} do
      {nil, _armed} ->
        {:noreply, socket}

      {alter, nil} ->
        ids = for %Note{id: id} <- selected_events(socket.assigns.session), do: id
        {:noreply, edit(socket, &Editing.set_alter(&1, &2, ids, alter))}

      {alter, armed} ->
        {:noreply, assign(socket, :armed, EditorPalette.set_accidental(armed, alter))}
    end
  end

  def handle_event("toggle_insert", _params, socket) do
    {:noreply, assign(socket, :insert?, !socket.assigns.insert?)}
  end

  ## Placing

  def handle_event("place", params, %{assigns: %{armed: %{} = armed}} = socket) do
    insert? = socket.assigns.insert?

    case EditorPlacement.parse(params) do
      {:ok, target} ->
        result = apply_edit(socket, &EditorPlacement.place(&1, &2, armed, target, insert?))
        {:noreply, placed(result)}

      :error ->
        {:noreply, put_flash(socket, :error, error_message(:invalid))}
    end
  end

  def handle_event("place", _params, socket), do: {:noreply, socket}

  ## Selection

  def handle_event("select", %{"ids" => [id], "add" => true}, socket) when is_binary(id) do
    {:noreply, update(socket, :session, &Session.toggle(&1, id))}
  end

  def handle_event("select", %{"ids" => ids} = params, socket) when is_list(ids) do
    ids = Enum.filter(ids, &is_binary/1)
    {:noreply, update(socket, :session, &Session.select(&1, ids, params["add"] == true))}
  end

  def handle_event("select_range", %{"from" => from, "to" => to}, socket)
      when is_integer(from) and is_integer(to) do
    %{session: session} = socket.assigns
    ids = Editing.select_range(session.score, session.ctx, min(from, to), max(from, to))
    {:noreply, assign(socket, :session, Session.select(session, ids, false))}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, update(socket, :session, &Session.clear_selection/1)}
  end

  def handle_event("set_last_click", %{"at" => at}, socket) when is_integer(at) and at >= 0 do
    {:noreply, assign(socket, :last_click, at)}
  end

  ## Changing the selection

  # ↑/↓ by scale step (Shift: octave, Ctrl: semitone); ←/→ by beat.
  def handle_event("move", %{"dir" => dir}, socket) when dir in ~w(left right) do
    ids = selected_ids(socket)
    beats = beats(dir)
    {:noreply, edit_selection(socket, &Editing.shift(&1, &2, ids, beats))}
  end

  def handle_event("move", %{"dir" => dir} = params, socket) when dir in ~w(up down) do
    fun = EditorCommands.transpose(selected_ids(socket), params["by"] || "step", dir)
    {:noreply, edit_selection(socket, fun)}
  end

  def handle_event("delete", _params, socket) do
    ids = selected_ids(socket)
    {:noreply, edit_selection(socket, &Editing.delete(&1, &2, ids))}
  end

  def handle_event("copy", _params, socket), do: {:noreply, copy(socket)}

  def handle_event("cut", _params, socket) do
    ids = selected_ids(socket)

    {:noreply,
     socket
     |> copy()
     |> edit_selection(&Editing.delete(&1, &2, ids))}
  end

  def handle_event(
        "paste",
        params,
        %{assigns: %{session: %{clipboard: %{} = clipboard}}} = socket
      ) do
    {:noreply, edit(socket, EditorCommands.paste(clipboard, paste_at(socket, params["at"])))}
  end

  def handle_event("paste", _params, socket), do: {:noreply, socket}

  ## Pick-up and ties

  def handle_event("drop", %{"ids" => ids, "steps" => steps} = params, socket)
      when is_list(ids) and is_integer(steps) do
    ids = Enum.filter(ids, &is_binary/1)
    alter = EditorPalette.alter(to_string(params["alter"]))
    {:noreply, edit(socket, EditorCommands.drop(ids, steps, alter))}
  end

  def handle_event("tie", %{"from" => from, "to" => to}, socket)
      when is_binary(from) and is_binary(to) do
    {:noreply, placed(apply_edit(socket, &Editing.tie(&1, &2, from, to)))}
  end

  ## Context menu

  def handle_event("open_menu", %{"id" => id, "x" => x, "y" => y} = params, socket)
      when is_binary(id) and is_number(x) and is_number(y) do
    case find_event(socket.assigns.session, id) do
      nil -> {:noreply, socket}
      event -> {:noreply, assign(socket, :menu, menu_for(socket, event, params))}
    end
  end

  def handle_event("close_menu", _params, socket), do: {:noreply, assign(socket, :menu, nil)}

  def handle_event("menu_copy", _params, %{assigns: %{menu: %{} = menu}} = socket) do
    {:noreply,
     socket
     |> select_menu_events(menu)
     |> copy()
     |> assign(:menu, nil)}
  end

  def handle_event("menu_cut", _params, %{assigns: %{menu: %{} = menu}} = socket) do
    {:noreply,
     socket
     |> select_menu_events(menu)
     |> copy()
     |> edit(&Editing.delete(&1, &2, menu.ids))
     |> assign(:menu, nil)}
  end

  def handle_event(event, params, %{assigns: %{menu: %{} = menu}} = socket)
      when event in @menu_events do
    fun = EditorCommands.menu(event, params, menu, socket.assigns.insert?)

    {:noreply,
     socket
     |> edit(fun)
     |> assign(:menu, nil)}
  end

  ## Measures

  def handle_event("insert_measure", %{"index" => index}, socket) do
    case parse_index(index) do
      {:ok, index} -> {:noreply, edit(socket, &Editing.insert_measure(&1, &2, index))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("delete_measure", %{"index" => index}, socket) do
    case parse_index(index) do
      {:ok, index} -> {:noreply, edit(socket, &Editing.delete_measure(&1, &2, index))}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("add_measure", _params, socket) do
    {:noreply, edit(socket, fn score, _ctx -> Editing.append_measure(score) end)}
  end

  ## Saving

  # On the draft, Save means "save as a new composition".
  def handle_event("save", _params, %{assigns: %{version: %Version{id: nil}}} = socket) do
    {:noreply, open_save_as(socket)}
  end

  def handle_event("save", _params, socket) do
    %{current_scope: scope, version: version, session: session} = socket.assigns

    case Library.save_version(scope, version, version_attrs(socket)) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> assign(version: %{saved | key: version.key}, session: Session.saved(session))
         |> put_flash(:info, "Saved")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  def handle_event("save_new_version", _params, %{assigns: %{version: %Version{id: id}}} = socket)
      when not is_nil(id) do
    %{current_scope: scope, version: version} = socket.assigns

    case Library.save_new_version(scope, version.key, version_attrs(socket)) do
      {:ok, saved} ->
        {:noreply, saved_and_open(socket, saved, "Saved as version #{saved.number}")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  def handle_event("open_save_as", _params, socket), do: {:noreply, open_save_as(socket)}

  def handle_event("close_save_as", _params, socket) do
    {:noreply, assign(socket, :save_as_form, nil)}
  end

  def handle_event("validate_save_as", %{"composition" => params}, socket) do
    changeset = Library.change_composition(socket.assigns.current_scope, %Composition{}, params)
    {:noreply, assign(socket, :save_as_form, to_form(changeset, action: :validate))}
  end

  def handle_event("save_as", %{"composition" => params}, socket) do
    %{current_scope: scope, session: %{ctx: ctx}} = socket.assigns
    key_attrs = %{sf: ctx.sf, mode: ctx.mode}

    case Library.create_composition(scope, params, key_attrs, version_attrs(socket)) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> assign(:save_as_form, nil)
         |> saved_and_open(saved, "Saved")}

      {:error, %Ecto.Changeset{data: %Composition{}} = changeset} ->
        {:noreply, assign(socket, :save_as_form, to_form(changeset, action: :insert))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  ## Score settings

  def handle_event("open_settings", _params, socket) do
    %{session: session, tempo_text: tempo_text, instrument: instrument} = socket.assigns
    params = EditorSettings.params(session.ctx, tempo_text, instrument)
    {:noreply, assign(socket, :settings_form, to_form(params, as: :settings))}
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, :settings_form, nil)}
  end

  # Settings apply at once; a new key is confirmed in the transpose dialog.
  def handle_event("apply_settings", %{"settings" => params}, socket) do
    case EditorSettings.validate(params) do
      {:ok, key, fields} ->
        {:noreply, apply_settings(socket, params, key, fields)}

      {:error, errors} ->
        form = to_form(params, as: :settings, errors: errors, action: :validate)
        {:noreply, assign(socket, :settings_form, form)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_transpose", _params, socket) do
    {:noreply, assign(socket, :pending_key, nil)}
  end

  def handle_event(
        "transpose_key",
        %{"direction" => dir},
        %{assigns: %{pending_key: {sf, mode}}} = socket
      )
      when dir in ~w(nearest up down) do
    %{session: session} = socket.assigns
    from = {session.ctx.sf, session.ctx.mode}
    socket = assign(socket, :pending_key, nil)

    case Transpose.to_key(session.score, from, {sf, mode}, String.to_existing_atom(dir)) do
      {:ok, score} ->
        session = Session.change_context(session, %{session.ctx | sf: sf, mode: mode}, score)

        {:noreply,
         socket
         |> assign(:session, session)
         |> in_new_key(sf, mode)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  ## Playback

  # The browser plays the events (Tone.js) and highlights each note as it
  # sounds; Play while playing stops.
  def handle_event("play", _params, %{assigns: %{playing?: true}} = socket) do
    {:noreply,
     socket
     |> assign(:playing?, false)
     |> push_event("stop", %{})}
  end

  def handle_event("play", _params, socket) do
    %{session: session} = socket.assigns

    case Playback.events(session.score, session.ctx, from: play_from(session)) do
      [] ->
        {:noreply, socket}

      events ->
        {:noreply,
         socket
         |> assign(:playing?, true)
         |> push_event("play", %PlaybackPayload{events: events})}
    end
  end

  def handle_event("playback_ended", _params, socket) do
    {:noreply, assign(socket, :playing?, false)}
  end

  ## History

  def handle_event("undo", _params, socket) do
    {:noreply,
     socket
     |> update(:session, &Session.undo/1)
     |> assign_layout()}
  end

  def handle_event("redo", _params, socket) do
    {:noreply,
     socket
     |> update(:session, &Session.redo/1)
     |> assign_layout()}
  end

  ## Preferences

  def handle_event("set_score_layout" = event, params, socket) do
    {:noreply,
     event
     |> ScorePreferences.apply_event(params, socket)
     |> assign_layout()}
  end

  # Events from the browser that don't fit the current state (a menu action
  # with no menu open, malformed params) are ignored rather than crashing
  # the editor. Keep this clause last.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  ## Editing

  # Runs `fun.(score, ctx)` through the session. On error the score stays
  # as it was and the reason is shown.
  defp apply_edit(socket, fun) do
    case Session.edit(socket.assigns.session, fun) do
      {:ok, session, _extra} ->
        {:ok,
         socket
         |> clear_flash()
         |> assign(:session, session)
         |> assign_layout()}

      {:error, reason} ->
        {:error, put_flash(socket, :error, error_message(reason))}
    end
  end

  # `apply_edit/2` when the outcome doesn't matter beyond the socket.
  defp edit(socket, fun) do
    {_outcome, socket} = apply_edit(socket, fun)
    socket
  end

  # A placement or tie that worked disarms the palette unless it's locked.
  defp placed({:ok, socket}), do: disarm_unless_locked(socket)
  defp placed({:error, socket}), do: socket

  # Edits the selection; with nothing selected there is nothing to do.
  defp edit_selection(socket, fun) do
    if MapSet.size(socket.assigns.session.selection) == 0, do: socket, else: edit(socket, fun)
  end

  @messages %{
    measure_full: "That bar is full",
    overlap: "Something is already there",
    duplicate: "That note is already there",
    out_of_range: "That would go outside the piano's range",
    not_tieable: "Only touching notes of the same pitch can be tied",
    last_measure: "A score needs at least one bar",
    unrepresentable: "That length can't be written as one note",
    no_such_measure: "That bar no longer exists",
    before_start: "That would move before the start",
    not_found: "That note no longer exists",
    pickup_bar: "Remove the pickup in the score settings first"
  }

  @doc "What to tell the user when an edit is refused for `reason`."
  @spec error_message(atom()) :: String.t()
  def error_message(reason), do: Map.get(@messages, reason, "That can't be done here")

  defp arm(socket, {:ok, armed}), do: assign(socket, :armed, armed)
  defp arm(socket, :error), do: socket

  defp disarm_unless_locked(%{assigns: %{armed: %{locked?: true}}} = socket), do: socket
  defp disarm_unless_locked(socket), do: assign(socket, :armed, nil)

  defp beats("left"), do: -1
  defp beats("right"), do: 1

  defp parse_index(index) do
    case Integer.parse(to_string(index)) do
      {index, ""} -> {:ok, index}
      _ -> :error
    end
  end

  defp selected_ids(socket), do: MapSet.to_list(socket.assigns.session.selection)

  # Playback starts at the earliest selected event, else at the beginning.
  defp play_from(%Session{} = session) do
    session.score
    |> Timeline.flatten(session.ctx)
    |> Enum.filter(&(&1.event.id in session.selection))
    |> Enum.map(& &1.start)
    |> Enum.min(fn -> 0 end)
  end

  defp selected_events(%Session{score: score, selection: selection}) do
    for m <- score.measures, event <- m.notes ++ m.rests, event.id in selection, do: event
  end

  defp find_event(%Session{score: score}, id) do
    Enum.find_value(score.measures, fn m -> Enum.find(m.notes ++ m.rests, &(&1.id == id)) end)
  end

  defp select_menu_events(socket, %ContextMenu{ids: ids}) do
    update(socket, :session, &Session.select(&1, ids, false))
  end

  defp menu_for(socket, event, params) do
    {kind, ids} = menu_target(socket.assigns.session.selection, event)

    step =
      case EditorPlacement.parse(Map.merge(%{"measure" => 0, "offset" => 0}, params)) do
        {:ok, target} -> target.step
        :error -> nil
      end

    %ContextMenu{id: event.id, ids: ids, kind: kind, x: params["x"], y: params["y"], step: step}
  end

  # Right-clicking a selected event opens the menu for the whole selection.
  defp menu_target(selection, event) do
    case MapSet.member?(selection, event.id) do
      true -> {:selection, MapSet.to_list(selection)}
      false -> {event_kind(event), [event.id]}
    end
  end

  defp event_kind(%Note{}), do: :note
  defp event_kind(_rest), do: :rest

  defp copy(socket) do
    %{session: session} = socket.assigns

    if MapSet.size(session.selection) == 0 do
      socket
    else
      clipboard = Editing.copy(session.score, session.ctx, selected_ids(socket))
      assign(socket, :session, %{session | clipboard: clipboard})
    end
  end

  # Where to paste: the given tick, else the last click, else straight
  # after the selection, else the start; never past the end of the score
  # (the browser's numbers are untrusted).
  defp paste_at(socket, at) do
    %{session: session} = socket.assigns
    min(wanted_paste_at(socket, at), Timeline.end_tick(session.score, session.ctx))
  end

  defp wanted_paste_at(_socket, at) when is_integer(at) and at >= 0, do: at
  defp wanted_paste_at(%{assigns: %{last_click: at}}, _at) when is_integer(at), do: at

  defp wanted_paste_at(socket, _at) do
    %{session: session} = socket.assigns

    session.score
    |> Timeline.flatten(session.ctx)
    |> Enum.filter(&(&1.event.id in session.selection))
    |> Enum.map(&(&1.start + &1.ticks))
    |> Enum.max(fn -> 0 end)
  end

  ## Settings helpers

  defp apply_settings(socket, params, key, fields) do
    case EditorSettings.apply(socket.assigns.session, fields) do
      {:ok, session} ->
        %{tempo_text: old_text, instrument: old_instrument} = socket.assigns
        tempo_text = EditorSettings.tempo_text(params["tempo_text"])

        session =
          session
          |> touched(tempo_text, old_text)
          |> touched(fields.instrument, old_instrument)

        socket
        |> assign(
          session: session,
          settings_form: nil,
          pending_key: pending_key(key, session.ctx)
        )
        |> assign(:tempo_text, tempo_text)
        |> assign_instrument(fields.instrument)
        |> assign_layout()

      {:error, reason} ->
        put_flash(socket, :error, error_message(reason))
    end
  end

  # The marking and instrument live beside the session; changing them is
  # still unsaved work.
  defp touched(session, same, same), do: session
  defp touched(session, _new, _old), do: %{session | dirty?: true}

  defp assign_instrument(%{assigns: %{instrument: program}} = socket, program), do: socket

  defp assign_instrument(socket, program) do
    assign(socket, instrument: program, instrument_source: InstrumentSource.for_program(program))
  end

  # A key other than the current one waits for the transpose dialog.
  defp pending_key({sf, mode}, %Context{sf: sf, mode: mode}), do: nil
  defp pending_key(key, _ctx), do: key

  ## Saving helpers

  defp version_attrs(socket) do
    %{session: session, tempo_text: tempo_text, instrument: instrument} = socket.assigns
    EditorSettings.version_attrs(session, tempo_text, instrument)
  end

  defp open_save_as(socket) do
    changeset = Library.change_composition(socket.assigns.current_scope, %Composition{})
    assign(socket, :save_as_form, to_form(changeset))
  end

  # A key change on a saved version is stored as a new version in that key;
  # on the draft it just applies.
  defp in_new_key(%{assigns: %{version: %Version{id: nil}}} = socket, _sf, _mode) do
    assign_layout(socket)
  end

  defp in_new_key(socket, sf, mode) do
    %{current_scope: scope, composition: composition} = socket.assigns

    case Library.save_in_key(scope, composition, %{sf: sf, mode: mode}, version_attrs(socket)) do
      {:ok, saved} -> saved_and_open(socket, saved, "Saved in #{Key.name(sf, mode)}")
      {:error, changeset} -> put_flash(socket, :error, changeset_message(changeset))
    end
  end

  defp saved_and_open(socket, saved, message) do
    socket
    |> assign(:session, Session.saved(socket.assigns.session))
    |> put_flash(:info, message)
    |> push_navigate(to: version_path(saved.key.composition.id, saved.key, saved.number))
  end

  defp changeset_message(%Ecto.Changeset{errors: [{field, {message, _opts}} | _]}) do
    "Couldn't save: #{Phoenix.Naming.humanize(field)} #{message}"
  end

  defp changeset_message(_changeset), do: "Couldn't save"

  # `:engraved`, not `:layout`: LiveView reserves the `layout` assign.
  defp assign_layout(socket) do
    %{session: session, current_scope: scope} = socket.assigns
    width = layout_width(scope.user.score_layout)
    assign(socket, :engraved, Layout.layout(session.score, session.ctx, width: width))
  end

  defp export_path(version, extension) do
    version_path(version.key.composition.id, version.key, version.number) <> "/score.#{extension}"
  end
end
