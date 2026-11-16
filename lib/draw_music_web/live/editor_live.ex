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

  import DrawMusicWeb.{EditorComponents, LibraryComponents}
  import DrawMusicWeb.ScoreComponents, only: [layout_width: 1]

  import DrawMusicWeb.PreferencesComponents, only: [preferences_panel: 1]

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}

  alias DrawMusic.Music.{
    Context,
    KeySuggestion,
    Rekey,
    Score,
    Session,
    Transpose
  }

  alias DrawMusicWeb.{
    DetailsDialog,
    EditorGeometry,
    EditorSaving,
    EditorSettings,
    InkPicker,
    LayoutToggle,
    PreferenceSwitch,
    ReadingAids,
    ScoreSvg,
    Shortcuts,
    VersionLookup
  }

  alias DrawMusicWeb.Editor.{
    NoteMenu,
    Palette,
    SaveAsDialog,
    SaveMenu,
    ScoreCanvas,
    SettingsDialog,
    TempoDialog,
    Transport,
    TransposeDialog
  }

  @draft_measures 4

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      preferences_patch={"#{@path}?panel=preferences"}
      wide
    >
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

      <.live_component
        module={Palette}
        id="editor-palette"
        armed={@armed}
        row_kind={@row_kind}
        insert?={@insert?}
        selection={Session.selection_ids(@session)}
        can_undo?={@session.undo != []}
        can_redo?={@session.redo != []}
        mode={@session.ctx.mode}
        editor_mode={@editor_mode}
        key_suggestion={@key_suggestion}
      >
        <:play_controls>
          <.live_component
            module={Transport}
            id="transport"
            score={@session.score}
            ctx={@session.ctx}
            selection={@session.selection}
            engraved={@engraved}
            editor_mode={@editor_mode}
            instrument={@instrument}
            lines?={@current_scope.user.score_layout == :page}
          />
        </:play_controls>
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
      </.live_component>

      <div
        id="score-paper"
        class={[
          "rounded-box border border-base-300 p-4 shadow-sm transition-colors",
          if(@current_scope.user.score_layout == :strip, do: "overflow-x-auto")
        ]}
        style="background-color: var(--score-paper)"
      >
        <.live_component
          module={ScoreCanvas}
          id="score-canvas"
          session={@session}
          engraved={@engraved}
          pieces={@pieces}
          geometry_json={@geometry_json}
          armed={@armed}
          insert?={@insert?}
          editor_mode={@editor_mode}
          layout={@current_scope.user.score_layout}
          loading?={@score_loading?}
          show_note_names?={@current_scope.user.show_note_names}
        />
        <.unsaved_guard dirty?={@session.dirty?} />
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
        <.preferences_panel :if={@preferences?} scope={@current_scope} close={@path} />
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
     |> assign(armed: nil, row_kind: :note, insert?: true)
     # At most one dialog (or the right-click menu) is open at a time.
     |> assign(:dialog, nil)
     |> assign(:editor_mode, :edit)
     # The tempo marking and instrument aren't part of the score's Context;
     # they're saved beside it.
     |> assign(:tempo_text, version.tempo_text)
     |> assign(:instrument, version.instrument)
     |> assign_placeholder()
     |> lay_out_after_join()}
  end

  # The Preferences panel is part of the address (`?panel=preferences`), so
  # opening and closing it are patches: the editor, unsaved work included,
  # stays as it is.
  @impl true
  def handle_params(params, uri, socket) do
    {:noreply,
     socket
     |> assign(:path, URI.parse(uri).path)
     |> assign(:preferences?, params["panel"] == "preferences")}
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

  # Play mode doesn't edit the score, step through its history or arm the
  # palette.
  def handle_info({:editor, intent}, %{assigns: %{editor_mode: :play}} = socket)
      when is_tuple(intent) and elem(intent, 0) in [:edit, :history, :palette] do
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

  def handle_info({:editor, {:palette, changes}}, socket) do
    {:noreply, assign(socket, Map.take(changes, [:armed, :row_kind, :insert?]))}
  end

  # (Leaving Play mode stops playback: `Editor.Transport` sees the mode.) A
  # range selected for playback shouldn't become an edit target, so entering
  # Edit narrows the selection to its first event; entering Play keeps it.
  def handle_info({:editor, {:mode, mode}}, socket) when mode in [:edit, :play] do
    {:noreply,
     socket
     |> assign(editor_mode: mode, armed: nil)
     |> close_menu()
     |> narrow_selection_for(mode)}
  end

  def handle_info({:editor, {:history, direction}}, socket) when direction in [:undo, :redo] do
    {:noreply,
     socket
     |> update(:session, &history_step(&1, direction))
     |> assign_layout()}
  end

  # The playback instrument, made the version's: unsaved work until saved.
  def handle_info({:editor, {:instrument, program}}, socket) do
    %{session: session, instrument: old} = socket.assigns

    {:noreply, assign(socket, session: touched(session, program, old), instrument: program)}
  end

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

  # Suggest key: the same sounds in the chosen key, saved in it as a new key
  # change would be.
  def handle_info({:editor, {:rekey, {sf, mode}}}, socket) do
    %{session: session} = socket.assigns
    score = Rekey.to_signature(session.score, sf)
    session = Session.change_context(session, %{session.ctx | sf: sf, mode: mode}, score)

    {:noreply,
     socket
     |> assign(:session, session)
     |> in_new_key(sf, mode)}
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

  # Another preference, from the Preferences panel: the editor follows it.
  # The ink and the placing aid are read from the user when drawn; the staff
  # letters are part of the pieces, so those are drawn again (not engraved).
  def handle_info({InkPicker, {:updated, user}}, socket) do
    {:noreply, assign(socket, :current_scope, %{socket.assigns.current_scope | user: user})}
  end

  def handle_info({PreferenceSwitch, {:updated, user}}, socket) do
    {:noreply,
     socket
     |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
     |> assign_pieces()}
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

  ## Composition details

  @impl true
  def handle_event("edit_details", _params, socket) do
    {:noreply, assign(socket, :dialog, :details)}
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
         |> assign_layout(), extra}

      {:error, reason} ->
        {:error, put_flash(socket, :error, error_message(reason))}
    end
  end

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

  defp history_step(session, :undo), do: Session.undo(session)
  defp history_step(session, :redo), do: Session.redo(session)

  defp narrow_selection_for(socket, :edit),
    do: update(socket, :session, &Session.collapse_selection/1)

  defp narrow_selection_for(socket, :play), do: socket

  # Switching modes closes a right-click menu, but not a dialog.
  defp close_menu(%{assigns: %{dialog: {:menu, _menu}}} = socket),
    do: assign(socket, :dialog, nil)

  defp close_menu(socket), do: socket

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
        |> assign(:instrument, fields.instrument)
        |> assign_layout()

      {:error, reason} ->
        put_flash(socket, :error, error_message(reason))
    end
  end

  # The marking and instrument live beside the session; changing them is
  # still unsaved work.
  defp touched(session, same, same), do: session
  defp touched(session, _new, _old), do: %{session | dirty?: true}

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
    %{current_scope: scope, composition: composition, version: old} = socket.assigns

    case Library.save_in_key(scope, composition, %{sf: sf, mode: mode}, version_attrs(socket)) do
      {:ok, saved} ->
        message =
          "Saved as #{Key.name(sf, mode)} v#{saved.number} " <>
            "(#{Key.name(old.key)} v#{old.number} is kept)"

        saved_and_open(socket, saved, message)

      {:error, changeset} ->
        put_flash(socket, :error, EditorSaving.error_message(changeset))
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
    |> assign_pieces()
    |> assign(:geometry_json, Jason.encode!(EditorGeometry.encode(engraved, ctx)))
    |> assign(:score_loading?, loading?)
    |> assign(:key_suggestion, KeySuggestion.suggest(score, {ctx.sf, ctx.mode}))
  end

  # The pieces drawn from the engraving, with the user's reading aids (only
  # here: the export draws the engraving without them).
  defp assign_pieces(socket) do
    %{engraved: engraved, current_scope: %{user: user}} = socket.assigns
    assign(socket, :pieces, ScoreSvg.pieces(ReadingAids.add(engraved, user), user.score_layout))
  end

  defp export_path(version, extension) do
    version_path(version.key.composition.id, version.key, version.number) <> "/score.#{extension}"
  end
end
