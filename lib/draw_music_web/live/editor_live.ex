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
    ScoreComponents
  }

  alias DrawMusic.Engraving.{Engraved, Layout}
  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}

  alias DrawMusic.Music.{
    Context,
    Editing,
    Note,
    Playback,
    Score,
    Session,
    TempoEditing,
    TempoMap,
    Timeline,
    Transpose
  }

  alias DrawMusicWeb.{
    ContextMenu,
    DetailsDialog,
    EditorCommands,
    EditorGeometry,
    EditorPalette,
    EditorPlacement,
    EditorSaving,
    EditorSettings,
    InstrumentSource,
    LayoutToggle,
    PlaybackPayload,
    ScoreSvg,
    Shortcuts,
    TempoTarget,
    VersionLookup
  }

  alias DrawMusicWeb.Editor.{
    NoteMenu,
    SaveAsDialog,
    SaveMenu,
    SettingsDialog,
    TempoDialog,
    TransposeDialog
  }

  @draft_measures 4
  # Everything that changes the score or arms the palette; Play mode ignores them.
  @edit_events ~w(arm arm_value arm_chord single_notes arm_tie toggle_rest toggle_dot set_accidental
                  toggle_insert place move delete cut paste drop tie open_menu
                  insert_measure delete_measure add_measure undo redo open_settings
                  select_all edit_tempo move_tempo resize_tempo)
  # The play controls; Edit mode ignores them.
  @play_events ~w(play rewind skip toggle_loop audition set_playback_instrument
                  use_playback_instrument)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <%!-- Version status and downloads sit on the title's row, at the right. --%>
      <header class="flex flex-wrap items-start justify-between gap-4">
        <div class="space-y-1">
          <div class="flex flex-wrap items-center gap-2">
            <h1 id="composition-name" class="text-2xl font-semibold">{@composition.name}</h1>
            <.details_button id="edit-details" />
          </div>
          <p :if={@composition.subtitle} class="opacity-80">{@composition.subtitle}</p>
          <p :if={credits(@composition) != ""} class="text-sm opacity-60">{credits(@composition)}</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <%= if @version.id do %>
            <.version_picker id="version-picker" composition={@composition} version={@version} />
          <% else %>
            <span id="unsaved" class="badge badge-ghost">Unsaved</span>
          <% end %>
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
        editor_mode={@editor_mode}
        playback={@playback}
        loop?={@loop?}
        lines?={@current_scope.user.score_layout == :page}
        instrument_name={@instrument_source.name}
        playback_instrument={@playback_instrument}
        version_instrument={@instrument}
        instrument_options={@instrument_options}
      >
        <:below_mode>
          <%!-- Its buttons are cells of the palette's grid, so Page and Strip
               line up under Edit and Play, the same widths. --%>
          <.live_component
            module={LayoutToggle}
            id="score-layout"
            scope={@current_scope}
            class="contents"
            button_class="row-start-2 h-auto w-full"
          />
        </:below_mode>
        <:trailing>
          <.live_component
            module={SaveMenu}
            id="saving"
            scope={@current_scope}
            version={@version}
            version_attrs={EditorSettings.version_attrs(@session, @tempo_text, @instrument)}
            dirty?={@session.dirty?}
          />
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
          data-geometry={@geometry_json}
          data-insert={to_string(@insert?)}
          data-armed={Jason.encode!(EditorGeometry.armed(@armed, @session.ctx))}
          data-dirty={to_string(@session.dirty?)}
          data-instrument={Jason.encode!(@instrument_source)}
          data-mode={@editor_mode}
          data-play-start={@editor_mode == :play && play_start(@session)}
          data-loading={to_string(@score_loading?)}
          data-layout={@current_scope.user.score_layout}
        >
          <.score
            id="score"
            layout={@engraved}
            pieces={ScoreSvg.select(@pieces, @session.selection)}
            strip?={@current_scope.user.score_layout == :strip}
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
          />
        </div>
        <.live_component
          :if={match?({:menu, _menu}, @dialog)}
          module={NoteMenu}
          id="note-menu"
          menu={elem(@dialog, 1)}
          insert?={@insert?}
          score={@session.score}
          ctx={@session.ctx}
        />
        <.help_dialog shortcuts={Shortcuts.for_mode(@editor_mode)} />
        <%!-- A saved composition's details are stored at once (they aren't
             part of the score, so not of its undo or its unsaved changes); a
             draft's are kept until its first save. --%>
        <.live_component
          :if={@dialog == :details}
          module={DetailsDialog}
          id="details"
          scope={@current_scope}
          composition={@composition}
          persist?={@version.id != nil}
        />
        <.live_component
          :if={@dialog == :save_as}
          module={SaveAsDialog}
          id="save-as"
          scope={@current_scope}
          composition={@composition}
          version={@version}
          key={%{sf: @session.ctx.sf, mode: @session.ctx.mode}}
          version_attrs={EditorSettings.version_attrs(@session, @tempo_text, @instrument)}
        />
        <.live_component
          :if={match?({:tempo, _target}, @dialog)}
          module={TempoDialog}
          id="tempo"
          target={elem(@dialog, 1)}
          ctx={@session.ctx}
        />
        <.live_component
          :if={@dialog == :settings}
          module={SettingsDialog}
          id="settings"
          ctx={@session.ctx}
          tempo_text={@tempo_text}
          instrument={@instrument}
        />
        <.live_component
          :if={match?({:transpose, _key}, @dialog)}
          module={TransposeDialog}
          id="transpose"
          key={elem(@dialog, 1)}
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
     |> assign(armed: nil, row_kind: :note, insert?: true, last_click: nil)
     # At most one dialog (or the right-click menu) is open at a time.
     |> assign(:dialog, nil)
     |> assign(playback: :idle, loop?: false, editor_mode: :edit)
     |> assign(:instrument_options, instrument_options())
     # The tempo marking and instrument aren't part of the score's Context;
     # they're saved beside it.
     |> assign(:tempo_text, version.tempo_text)
     |> assign_instrument(version.instrument)
     |> assign_placeholder()
     |> lay_out_after_join()}
  end

  # Engraving and drawing a long score takes seconds, more than joining the
  # LiveView may: the join answers with a placeholder, and the score follows
  # as an ordinary update (`handle_info(:lay_out, ...)`).
  defp lay_out_after_join(socket) do
    if connected?(socket), do: send(self(), :lay_out)
    socket
  end

  @impl true
  def handle_info(:lay_out, socket), do: {:noreply, assign_layout(socket)}

  # The details dialog's results (see `DrawMusicWeb.DetailsDialog`).
  def handle_info({DetailsDialog, {:saved, composition}}, socket) do
    {:noreply,
     socket
     |> assign(composition: composition, page_title: composition.name, dialog: nil)
     |> put_flash(:info, "Details saved.")}
  end

  def handle_info({DetailsDialog, :closed}, socket), do: {:noreply, assign(socket, :dialog, nil)}

  # The editor components' results (see `DrawMusicWeb.Editor.Intent`).
  # Play mode doesn't change the score's settings or its key.
  def handle_info({:editor, {intent, _key, _value}}, %{assigns: %{editor_mode: :play}} = socket)
      when intent in [:settings, :transpose] do
    {:noreply, socket}
  end

  # Play mode doesn't edit the score.
  def handle_info({:editor, edit}, %{assigns: %{editor_mode: :play}} = socket)
      when is_tuple(edit) and elem(edit, 0) == :edit do
    {:noreply, socket}
  end

  def handle_info({:editor, :close}, socket), do: {:noreply, assign(socket, :dialog, nil)}

  def handle_info({:editor, {:edit, fun}}, socket), do: {:noreply, edit(socket, fun)}

  def handle_info({:editor, {:session, fun}}, socket) do
    {:noreply, update(socket, :session, fun)}
  end

  def handle_info({:editor, {:edit, fun, :select}}, socket) do
    {:noreply, edit_and_select(socket, fun)}
  end

  def handle_info({:editor, {:flash, kind, message}}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  def handle_info({:editor, {:open, dialog}}, socket),
    do: {:noreply, assign(socket, :dialog, dialog)}

  # The version being edited was stored: carry on with it.
  def handle_info(
        {:editor, {:saved, %Version{id: id} = saved, message}},
        %{assigns: %{version: %Version{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(version: saved, session: Session.saved(socket.assigns.session))
     |> put_flash(:info, message)}
  end

  # A new version or composition: open it.
  def handle_info({:editor, {:saved, saved, message}}, socket) do
    {:noreply, saved_and_open(socket, saved, message)}
  end

  # Settings apply at once; a new key is confirmed in the transpose dialog.
  def handle_info({:editor, {:settings, key, fields}}, socket) do
    {:noreply, apply_settings(socket, key, fields)}
  end

  def handle_info({:editor, {:transpose, {sf, mode}, direction}}, socket) do
    %{session: session} = socket.assigns
    from = {session.ctx.sf, session.ctx.mode}
    socket = assign(socket, :dialog, nil)

    case Transpose.to_key(session.score, from, {sf, mode}, direction) do
      {:ok, score} ->
        session = Session.change_context(session, %{session.ctx | sf: sf, mode: mode}, score)

        {:noreply,
         socket
         |> assign(:session, session)
         |> stop_playback()
         |> in_new_key(sf, mode)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  # A new layout preference: the score is laid out again in it.
  def handle_info({LayoutToggle, {:updated, user}}, socket) do
    {:noreply,
     socket
     |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
     |> assign_layout()}
  end

  defp load(:new, _scope, _params) do
    composition = %Composition{name: EditorSaving.untitled(), keys: []}
    key = %Key{sf: 0, mode: :major, composition: composition}
    {composition, %Version{key: key, score: Score.new(@draft_measures)}, composition.name}
  end

  defp load(:show, scope, params) do
    version = VersionLookup.fetch!(scope, params)
    composition = Library.get_composition!(scope, version.key.composition.id)
    {composition, version, "#{composition.name} · #{Key.name(version.key)} v#{version.number}"}
  end

  ## Modes

  @impl true
  def handle_event(event, _params, %{assigns: %{editor_mode: :play}} = socket)
      when event in @edit_events do
    {:noreply, socket}
  end

  def handle_event(event, _params, %{assigns: %{editor_mode: :edit}} = socket)
      when event in @play_events do
    {:noreply, socket}
  end

  # Leaving Play mode stops playback; the play controls go with it. A range
  # selected for playback shouldn't become an edit target, so entering Edit
  # narrows the selection to its first event; entering Play keeps it, to play.
  def handle_event("toggle_mode", params, socket) do
    mode = next_mode(params["mode"], socket.assigns.editor_mode)

    {:noreply,
     socket
     |> assign(editor_mode: mode, armed: nil)
     |> close_menu()
     |> narrow_selection_for(mode)
     |> stop_unless_playing_mode()}
  end

  # The playback instrument is for listening only; it starts as the
  # version's and lasts until the editor is reopened.
  def handle_event("set_playback_instrument", %{"instrument" => value}, socket) do
    case Integer.parse(to_string(value)) do
      {program, ""} when program in 0..127 ->
        {:noreply,
         socket
         |> stop_playback()
         |> assign_playback_instrument(program)}

      _invalid ->
        {:noreply, socket}
    end
  end

  def handle_event("use_playback_instrument", _params, socket) do
    %{playback_instrument: program, session: session} = socket.assigns

    {:noreply,
     socket
     |> assign(:session, touched(session, program, socket.assigns.instrument))
     |> assign(:instrument, program)}
  end

  # Play mode: a click on a note sounds its chord and makes it the start point.
  def handle_event("audition", %{"id" => id}, %{assigns: %{editor_mode: :play}} = socket)
      when is_binary(id) do
    %{session: session} = socket.assigns

    case Playback.chord_at(session.score, session.ctx, id) do
      [] ->
        {:noreply, socket}

      events ->
        {:noreply,
         socket
         |> reselected(&Session.select(&1, [id], false))
         |> push_event("audition", %PlaybackPayload{
           events: events,
           span: Enum.max(Enum.map(events, & &1.duration)),
           loop: false
         })}
    end
  end

  ## Palette

  def handle_event("arm", %{"kind" => kind, "value" => value}, socket) do
    {:noreply, arm(socket, EditorPalette.arm(socket.assigns.armed, kind, value))}
  end

  def handle_event("arm_value", %{"value" => value}, socket) do
    kind = Atom.to_string(socket.assigns.row_kind)
    {:noreply, arm(socket, EditorPalette.arm(socket.assigns.armed, kind, value))}
  end

  # Chords don't apply to rests. With nothing armed and notes selected, a
  # chord turns the selected notes into that chord; otherwise it turns chord
  # mode on (or, picked again, off), whichever of length and chord came first.
  def handle_event("arm_chord", _params, %{assigns: %{row_kind: :rest}} = socket) do
    {:noreply, socket}
  end

  def handle_event("arm_chord", params, socket) do
    %{armed: armed, session: session} = socket.assigns

    case {EditorPalette.chord(params), armed, MapSet.size(session.selection)} do
      {:error, _armed, _selected} ->
        {:noreply, socket}

      {{:ok, chord}, nil, selected} when selected > 0 ->
        {:noreply, edit_and_select(socket, EditorCommands.chordify(selected_ids(socket), chord))}

      {{:ok, chord}, armed, _selected} ->
        {:noreply, assign(socket, :armed, EditorPalette.arm_chord(armed, chord))}
    end
  end

  def handle_event("single_notes", _params, socket) do
    {:noreply, update(socket, :armed, &EditorPalette.single_notes/1)}
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
    events = Session.selected_events(socket.assigns.session)
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
        ids = for %Note{id: id} <- Session.selected_events(socket.assigns.session), do: id
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
      # (A press on a note or rest itself selects it: the hook sends `select`.)
      {:ok, target} ->
        {:noreply,
         placed(apply_edit(socket, &EditorPlacement.place(&1, &2, armed, target, insert?)))}

      :error ->
        {:noreply, put_flash(socket, :error, error_message(:invalid))}
    end
  end

  def handle_event("place", _params, socket), do: {:noreply, socket}

  ## Selection

  def handle_event("select", %{"ids" => [id], "add" => true}, socket) when is_binary(id) do
    {:noreply, reselected(socket, &Session.toggle(&1, id))}
  end

  def handle_event("select", %{"ids" => ids} = params, socket) when is_list(ids) do
    ids = Enum.filter(ids, &is_binary/1)
    {:noreply, reselected(socket, &Session.select(&1, ids, params["add"] == true))}
  end

  def handle_event("select_range", %{"from" => from, "to" => to}, socket)
      when is_integer(from) and is_integer(to) do
    %{session: session} = socket.assigns
    ids = Editing.select_range(session.score, session.ctx, min(from, to), max(from, to))
    {:noreply, reselected(socket, &Session.select(&1, ids, false))}
  end

  # While a band is dragged: what letting go would select, for the hook to
  # light up. Nothing changes until it does.
  def handle_event("preview_range", %{"from" => from, "to" => to}, socket)
      when is_integer(from) and is_integer(to) do
    %{session: session} = socket.assigns
    ids = Editing.select_range(session.score, session.ctx, min(from, to), max(from, to))
    {:reply, %{ids: ids}, socket}
  end

  # Every note and rest, on both staves, and every tempo change.
  def handle_event("select_all", _params, socket) do
    %{session: session} = socket.assigns
    events = for entry <- Timeline.flatten(session.score, session.ctx), do: entry.event.id
    ids = events ++ TempoEditing.ids(session.score)
    {:noreply, reselected(socket, &Session.select(&1, ids, false))}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, reselected(socket, &Session.clear_selection/1)}
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
    {:noreply, edit_selection(socket, EditorCommands.delete(ids, socket.assigns.insert?))}
  end

  def handle_event("copy", _params, socket), do: {:noreply, copy(socket)}

  def handle_event("cut", _params, socket) do
    ids = selected_ids(socket)

    {:noreply,
     socket
     |> copy()
     |> edit_selection(EditorCommands.delete(ids, socket.assigns.insert?))}
  end

  def handle_event(
        "paste",
        params,
        %{assigns: %{session: %{clipboard: %{} = clipboard}}} = socket
      ) do
    %{session: session, last_click: last_click} = socket.assigns
    at = Session.paste_at(session, params["at"], last_click)
    {:noreply, edit(socket, EditorCommands.paste(clipboard, at))}
  end

  def handle_event("paste", _params, socket), do: {:noreply, socket}

  ## Pick-up and ties

  def handle_event("drop", %{"ids" => ids, "steps" => steps} = params, socket)
      when is_list(ids) and is_integer(steps) do
    ids = Enum.filter(ids, &is_binary/1)
    alter = EditorPalette.alter(to_string(params["alter"]))
    {:noreply, edit_and_select(socket, EditorCommands.drop(ids, steps, alter))}
  end

  # One note dragged on its own lands on whichever staff it was let go over.
  def handle_event("drop", %{"ids" => [id], "staff" => staff, "step" => step} = params, socket)
      when is_binary(id) and is_integer(step) do
    alter = EditorPalette.alter(to_string(params["alter"]))

    case EditorPlacement.staff(staff) do
      nil ->
        {:noreply, socket}

      staff ->
        {:noreply, edit_and_select(socket, EditorCommands.drop_on_staff(id, staff, step, alter))}
    end
  end

  def handle_event("tie", %{"from" => from, "to" => to}, socket)
      when is_binary(from) and is_binary(to) do
    {:noreply, placed(apply_edit(socket, &Editing.tie(&1, &2, from, to)))}
  end

  ## Context menu

  # A right-click anywhere in the music. The selection decides which menu
  # opens (`ContextMenu.subject/2`); `id` is what was under the pointer.
  def handle_event("open_menu", %{"x" => x, "y" => y} = params, socket)
      when is_number(x) and is_number(y) do
    %{session: session} = socket.assigns

    case ContextMenu.subject(session.selection, clicked_id(params)) do
      :none ->
        {:noreply, socket}

      {:selection, ids} ->
        {:noreply, assign(socket, :dialog, {:menu, ContextMenu.for_selection(ids, params)})}

      {:event, id} ->
        {:noreply, open_event_menu(socket, id, params)}
    end
  end

  ## Tempo changes

  def handle_event("edit_tempo", %{"id" => id}, socket) when is_binary(id) do
    {:noreply, open_tempo_change(socket, id)}
  end

  def handle_event("move_tempo", %{"id" => id, "tick" => tick}, socket)
      when is_binary(id) and is_integer(tick) do
    {:noreply, edit_and_select(socket, &with_ids(TempoEditing.move(&1, &2, id, tick), [id]))}
  end

  def handle_event("resize_tempo", %{"id" => id, "tick" => tick}, socket)
      when is_binary(id) and is_integer(tick) do
    {:noreply, edit_and_select(socket, &with_ids(TempoEditing.resize(&1, &2, id, tick), [id]))}
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
    {:noreply, edit(socket, &Editing.append_measure/2)}
  end

  ## Composition details

  def handle_event("edit_details", _params, socket) do
    {:noreply, assign(socket, :dialog, :details)}
  end

  ## Score settings

  def handle_event("open_settings", _params, socket) do
    {:noreply, assign(socket, :dialog, :settings)}
  end

  ## Playback

  # The browser plays the events (smplr, see audio.js) and highlights each
  # note as it sounds; pause, resume, rewind and loop happen there too.
  def handle_event("play", _params, %{assigns: %{playback: :playing}} = socket) do
    {:noreply,
     socket
     |> assign(:playback, :paused)
     |> push_event("pause", %{})}
  end

  # Paused (or paused and rewound to the start point): carry on from there.
  def handle_event("play", _params, %{assigns: %{playback: state}} = socket)
      when state in [:paused, :rewound] do
    {:noreply,
     socket
     |> assign(:playback, :playing)
     |> push_event("resume", %{})}
  end

  def handle_event("play", _params, socket), do: {:noreply, start_playback(socket)}

  # Paused, Rewind goes back to the start point and waits there: the button
  # offers Play again, not Resume.
  def handle_event("rewind", _params, %{assigns: %{playback: :paused}} = socket) do
    {:noreply,
     socket
     |> assign(:playback, :rewound)
     |> push_event("rewind", %{})}
  end

  def handle_event("rewind", _params, socket), do: {:noreply, push_event(socket, "rewind", %{})}

  def handle_event("toggle_loop", _params, socket) do
    loop? = !socket.assigns.loop?

    {:noreply,
     socket
     |> assign(:loop?, loop?)
     |> push_event("loop", %{on: loop?})}
  end

  # ⏩ the start of the next measure, ⏩⏩ of the next line of music; with
  # dir "back", ⏪ and ⏪⏪ the start of this or the previous one. Playing or
  # paused, the hook knows where it is and jumps; before playing, the start
  # point moves there (the first note or rest it begins with is selected).
  def handle_event("skip", %{"by" => by} = params, socket) when by in ~w(measure line) do
    back? = match?(%{"dir" => "back"}, params)

    case socket.assigns.playback do
      state when state in [:idle, :loading] -> {:noreply, skip_start(socket, by, back?)}
      _sounding -> {:noreply, push_event(socket, "skip", %{by: by, back: back?})}
    end
  end

  def handle_event("stop", _params, socket) do
    {:noreply,
     socket
     |> assign(:playback, :idle)
     |> push_event("stop", %{})}
  end

  def handle_event("playback_state", %{"state" => state}, socket) when is_binary(state) do
    {:noreply, playback_state(socket, state)}
  end

  def handle_event("playback_ended", _params, socket) do
    {:noreply, assign(socket, :playback, :idle)}
  end

  ## History

  def handle_event("undo", _params, socket) do
    {:noreply,
     socket
     |> update(:session, &Session.undo/1)
     |> stop_playback()
     |> assign_layout()}
  end

  def handle_event("redo", _params, socket) do
    {:noreply,
     socket
     |> update(:session, &Session.redo/1)
     |> stop_playback()
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
      {:ok, session, extra} ->
        {:ok,
         socket
         |> clear_flash()
         |> assign(:session, session)
         |> stop_playback()
         |> assign_layout(), extra}

      {:error, reason} ->
        {:error, put_flash(socket, :error, error_message(reason))}
    end
  end

  defp with_ids({:ok, score}, ids), do: {:ok, score, ids}
  defp with_ids(error, _ids), do: error

  # `apply_edit/2` when the outcome doesn't matter beyond the socket.
  defp edit(socket, fun) do
    case apply_edit(socket, fun) do
      {:ok, socket, _extra} -> socket
      {:error, socket} -> socket
    end
  end

  # For edits that give the ids of the notes they made or moved (a drop, a
  # chord from the selection): those notes end up selected.
  defp edit_and_select(socket, fun) do
    case apply_edit(socket, fun) do
      {:ok, socket, ids} -> update(socket, :session, &Session.select(&1, ids, false))
      {:error, socket} -> socket
    end
  end

  # The armed item stays armed after a placement or tie, until another
  # is picked or it's disarmed; `placed/1` just unwraps the outcome.
  defp placed({:ok, socket, _extra}), do: socket
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
    pickup_bar: "Remove the pickup in the score settings first",
    past_end: "That's past the end of the score",
    invalid_tempo: "A rit. or accel. has to end after it starts",
    same_tempo: "A rit. or accel. has to reach a different tempo",
    opening_beat: "The opening tempo is set in Score settings"
  }

  @doc "What to tell the user when an edit is refused for `reason`."
  @spec error_message(atom()) :: String.t()
  def error_message(reason), do: Map.get(@messages, reason, "That can't be done here")

  defp arm(socket, {:ok, armed}), do: assign(socket, :armed, armed)
  defp arm(socket, :error), do: socket

  defp next_mode("play", _current), do: :play
  defp next_mode("edit", _current), do: :edit
  defp next_mode(_toggle, :edit), do: :play
  defp next_mode(_toggle, :play), do: :edit

  defp beats("left"), do: -1
  defp beats("right"), do: 1

  defp parse_index(index) do
    case Integer.parse(to_string(index)) do
      {index, ""} -> {:ok, index}
      _ -> :error
    end
  end

  defp selected_ids(socket), do: Session.selection_ids(socket.assigns.session)

  ## Playback helpers

  defp start_playback(socket) do
    %{session: session, loop?: loop?} = socket.assigns
    {from, to} = Playback.span(session.score, session.ctx, session.selection)
    opts = [from: from, to: to]

    case Playback.events(session.score, session.ctx, opts) do
      [] ->
        put_flash(socket, :error, "Nothing to play here.")

      events ->
        map = TempoMap.new(session.score, session.ctx)

        payload = %PlaybackPayload{
          events: events,
          span: TempoMap.seconds(map, from, to),
          loop: loop?,
          anchors: TempoMap.anchors(map, from, to)
        }

        socket
        |> assign(:playback, :playing)
        |> push_event("play", payload)
    end
  end

  # Where Play would start: the hook shows the playhead there in Play mode.
  defp play_start(session) do
    {from, _to} = Playback.span(session.score, session.ctx, session.selection)
    from
  end

  defp skip_start(socket, by, back?) do
    %{session: session, engraved: engraved} = socket.assigns
    points = skip_points(engraved, by)

    with tick when is_integer(tick) <- Playback.skip_target(points, play_start(session), back?),
         id when is_binary(id) <- Playback.first_event_from(session.score, session.ctx, tick) do
      update(socket, :session, &Session.select(&1, [id], false))
    else
      _none -> socket
    end
  end

  defp skip_points(engraved, "measure"), do: Engraved.measure_starts(engraved)
  defp skip_points(engraved, "line"), do: Engraved.line_starts(engraved)

  # What the hook reports; names are only matched, never made atoms.
  defp playback_state(socket, "loading"), do: assign(socket, :playback, :loading)
  defp playback_state(socket, "playing"), do: assign(socket, :playback, :playing)
  defp playback_state(%{assigns: %{playback: :rewound}} = socket, "paused"), do: socket
  defp playback_state(socket, "paused"), do: assign(socket, :playback, :paused)
  defp playback_state(socket, "idle"), do: assign(socket, :playback, :idle)
  defp playback_state(socket, "ready"), do: loaded(socket)

  defp playback_state(socket, "fallback") do
    name = socket.assigns.instrument_source.name

    socket
    |> loaded()
    |> put_flash(:info, "#{name} isn't available; playing with the built-in synth.")
  end

  defp playback_state(socket, _unknown), do: socket

  defp loaded(%{assigns: %{playback: :loading}} = socket), do: assign(socket, :playback, :idle)
  defp loaded(socket), do: socket

  # Any change to the score stops playback: the browser's events are stale.
  defp stop_playback(%{assigns: %{playback: state}} = socket) when state in [:idle, :loading] do
    socket
  end

  defp stop_playback(socket) do
    socket
    |> assign(:playback, :idle)
    |> push_event("stop", %{})
  end

  # A new selection is what the next Play plays: a paused span is dropped,
  # so Play starts the new one instead of resuming the old.
  defp reselected(socket, fun) do
    socket
    |> update(:session, fun)
    |> drop_paused()
  end

  defp drop_paused(%{assigns: %{playback: state}} = socket) when state in [:paused, :rewound] do
    stop_playback(socket)
  end

  defp drop_paused(socket), do: socket

  defp narrow_selection_for(socket, :edit),
    do: update(socket, :session, &Session.collapse_selection/1)

  defp narrow_selection_for(socket, :play), do: socket

  defp stop_unless_playing_mode(%{assigns: %{editor_mode: :play}} = socket), do: socket
  defp stop_unless_playing_mode(socket), do: stop_playback(socket)

  # Switching modes closes a right-click menu, but not a dialog.
  defp close_menu(%{assigns: %{dialog: {:menu, _menu}}} = socket),
    do: assign(socket, :dialog, nil)

  defp close_menu(socket), do: socket

  # What was under a right-click; the browser sends none off the notes.
  defp clicked_id(%{"id" => id}) when is_binary(id), do: id
  defp clicked_id(_params), do: nil

  # A note or rest gets its own menu; a tempo mark opens its dialog.
  defp open_event_menu(socket, id, params) do
    %{session: session} = socket.assigns

    case Session.find_event(session, id) do
      nil ->
        open_tempo_change(socket, id)

      event ->
        start = Timeline.start_of(session.score, session.ctx, id)
        menu = %{ContextMenu.for_event(event, params) | tempo?: TempoEditing.changeable?(start)}
        assign(socket, :dialog, {:menu, menu})
    end
  end

  # The tempo dialog for an existing change, which becomes the selection.
  defp open_tempo_change(socket, id) do
    %{session: session} = socket.assigns

    case TempoEditing.find(session.score, id) do
      {:ok, change} ->
        target = TempoTarget.for_change(session.score, session.ctx, change)

        socket
        |> update(:session, &Session.select(&1, [id], false))
        |> assign(:dialog, {:tempo, target})

      {:error, _not_found} ->
        socket
    end
  end

  defp copy(socket), do: update(socket, :session, &Session.copy/1)

  ## Settings helpers

  defp apply_settings(socket, key, fields) do
    case EditorSettings.apply(socket.assigns.session, fields) do
      {:ok, session} ->
        %{tempo_text: old_text, instrument: old_instrument} = socket.assigns

        session =
          session
          |> touched(fields.tempo_text, old_text)
          |> touched(fields.instrument, old_instrument)

        socket
        |> assign(session: session, dialog: transpose_prompt(key, session.ctx))
        |> assign(:tempo_text, fields.tempo_text)
        |> assign_instrument(fields.instrument)
        |> stop_playback()
        |> assign_layout()

      {:error, reason} ->
        put_flash(socket, :error, error_message(reason))
    end
  end

  # The marking and instrument live beside the session; changing them is
  # still unsaved work.
  defp touched(session, same, same), do: session
  defp touched(session, _new, _old), do: %{session | dirty?: true}

  # A new version instrument (from the settings) is also what playback uses next.
  defp assign_instrument(%{assigns: %{instrument: program}} = socket, program), do: socket

  defp assign_instrument(socket, program) do
    socket
    |> assign(:instrument, program)
    |> assign_playback_instrument(program)
  end

  defp assign_playback_instrument(%{assigns: %{playback_instrument: program}} = socket, program) do
    socket
  end

  defp assign_playback_instrument(socket, program) do
    assign(socket,
      playback_instrument: program,
      instrument_source: InstrumentSource.for_program(program)
    )
  end

  # A key other than the current one waits for the transpose dialog; the
  # same key closes the settings with nothing more to ask.
  defp transpose_prompt({sf, mode}, %Context{sf: sf, mode: mode}), do: nil
  defp transpose_prompt(key, _ctx), do: {:transpose, key}

  ## Saving helpers

  defp version_attrs(socket) do
    %{session: session, tempo_text: tempo_text, instrument: instrument} = socket.assigns
    EditorSettings.version_attrs(session, tempo_text, instrument)
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
      {:error, changeset} -> put_flash(socket, :error, EditorSaving.error_message(changeset))
    end
  end

  defp saved_and_open(socket, saved, message) do
    socket
    |> assign(:session, Session.saved(socket.assigns.session))
    |> put_flash(:info, message)
    |> push_navigate(to: version_path(saved.key.composition.id, saved.key, saved.number))
  end

  # `:engraved`, not `:layout`: LiveView reserves the `layout` assign.
  defp assign_layout(socket) do
    %{session: session, current_scope: scope} = socket.assigns
    lay_out(socket, session.score, layout_width(scope.user.score_layout), false)
  end

  # Until the score is engraved (the static page, and the join), an empty
  # bar stands in, with a note that the score is loading.
  defp assign_placeholder(socket) do
    width = layout_width(socket.assigns.current_scope.user.score_layout)
    lay_out(socket, Score.new(), width, true)
  end

  defp lay_out(socket, score, width, loading?) do
    ctx = socket.assigns.session.ctx
    engraved = Layout.layout(score, ctx, width: width, marking: socket.assigns.tempo_text)

    # The score goes to the browser in pieces, each one finished piece of
    # SVG, not as a LiveView diff of every glyph and line: a long piece has
    # tens of thousands, and building those one by one in the browser takes
    # long enough for the connection to time out. Parsed whole, it's quick,
    # and only the pieces an edit changes are sent again.
    socket
    |> assign(:engraved, engraved)
    |> assign(:pieces, ScoreSvg.pieces(engraved, socket.assigns.current_scope.user.score_layout))
    |> assign(:geometry_json, Jason.encode!(EditorGeometry.encode(engraved, ctx)))
    |> assign(:score_loading?, loading?)
  end

  defp export_path(version, extension) do
    version_path(version.key.composition.id, version.key, version.number) <> "/score.#{extension}"
  end
end
