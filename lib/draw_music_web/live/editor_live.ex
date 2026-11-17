defmodule DrawMusicWeb.EditorLive do
  @moduledoc """
  The score editor, in the user's preferred layout (one long staff or
  page-style systems) to start with; the palette switches it for the
  session (`DrawMusicWeb.Editor.View`). `:show` opens a saved version; `:new` (the main
  page) starts a blank, unsaved composition: C major, 4/4, four empty
  measures.

  The score lives in a `DrawMusic.Music.Session` (selection, clipboard,
  undo/redo, unsaved changes); the palette state (armed item, note/rest
  row, Insert mode) is kept beside it. Every change goes through
  `apply_edit/2`; the edits themselves are built by
  `DrawMusicWeb.EditorCommands` and `DrawMusicWeb.EditorPlacement`.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.{EditorComponents, EditorPage}
  import DrawMusicWeb.LibraryComponents, only: [version_path: 3]
  import DrawMusicWeb.ScoreComponents, only: [layout_width: 1]

  import DrawMusicWeb.PreferencesComponents, only: [preferences_panel: 1]

  alias DrawMusic.Accounts
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
    LayoutToggle,
    PaperToggle,
    PreferencesForm,
    ReadingAids,
    ScoreSvg,
    Shortcuts,
    VersionLookup
  }

  alias DrawMusicWeb.Editor.{
    Drawing,
    Palette,
    PaletteState,
    SaveMenu,
    ScoreCanvas,
    Transport,
    VersionExtras,
    View
  }

  @draft_measures 4

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

  @impl true
  def handle_event("edit_details", _params, socket) do
    {:noreply, assign(socket, :dialog, :details)}
  end

  # Events from the browser that don't fit the current state (a menu action
  # with no menu open, malformed params) are ignored rather than crashing
  # the editor. Keep this clause last.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

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
    {:noreply, update(socket, :palette, &PaletteState.change(&1, changes))}
  end

  # (Leaving Play mode stops playback: `Editor.Transport` sees the mode.) A
  # range selected for playback shouldn't become an edit target, so entering
  # Edit narrows the selection to its first event; entering Play keeps it.
  def handle_info({:editor, {:mode, mode}}, socket) when mode in [:edit, :play] do
    {:noreply,
     socket
     |> assign(:editor_mode, mode)
     |> update(:palette, &PaletteState.change(&1, %{armed: nil}))
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
    %{session: session, extras: extras} = socket.assigns

    {:noreply,
     assign(socket,
       session: touched(session, program, extras.instrument),
       extras: %{extras | instrument: program}
     )}
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

  # The palette's Page / Strip: the score in that layout, for this session
  # only (the preference stays as it is).
  def handle_info({LayoutToggle, {:chosen, layout}}, socket) do
    {:noreply,
     socket
     |> update(:view, &%{&1 | layout: layout})
     |> assign_layout()}
  end

  # The Sheet button: the score on that paper, for this session only. The
  # colors are CSS (`data-paper`), so nothing is drawn again.
  def handle_info({PaperToggle, {:chosen, paper}}, socket) do
    {:noreply, update(socket, :view, &%{&1 | paper: paper})}
  end

  # The Preferences panel's form: the editor shows its preview; Save and
  # Cancel close the panel (closing puts back what's stored, `handle_params`).
  def handle_info({PreferencesForm, {:preview, user}}, socket) do
    {:noreply, follow_user(socket, user)}
  end

  def handle_info({PreferencesForm, {_saved_or_cancelled, user}}, socket) do
    {:noreply,
     socket
     |> follow_user(user)
     |> push_patch(to: socket.assigns.path, replace: true)}
  end

  # The Preferences panel is part of the address (`?panel=preferences`), so
  # opening and closing it are patches: the editor, unsaved work included,
  # stays as it is. However it's closed (Save, Cancel, or the browser's Back),
  # the editor goes back to the stored preferences, dropping any preview.
  @impl true
  def handle_params(params, uri, socket) do
    open? = params["panel"] == "preferences"

    {:noreply,
     socket
     |> assign(:path, URI.parse(uri).path)
     |> closing_preferences(Map.get(socket.assigns, :preferences?, false), open?)
     |> assign(:preferences?, open?)}
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
     |> assign(:palette, %PaletteState{})
     # At most one dialog (or the right-click menu) is open at a time.
     |> assign(:dialog, nil)
     |> assign(:editor_mode, :edit)
     |> assign(:extras, VersionExtras.from_version(version))
     |> assign(:view, View.from_user(socket.assigns.current_scope.user))
     |> assign_placeholder()
     |> lay_out_after_join()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      preferences_patch={"#{@path}?panel=preferences"}
      import_panel={@import_panel}
      paper={@view.paper}
      wide
    >
      <.editor_header composition={@composition} version={@version} instrument={@extras.instrument} />

      <.live_component
        module={Palette}
        id="editor-palette"
        armed={@palette.armed}
        row_kind={@palette.row_kind}
        insert?={@palette.insert?}
        selection={Session.selection_ids(@session)}
        can_undo?={@session.undo != []}
        can_redo?={@session.redo != []}
        mode={@session.ctx.mode}
        editor_mode={@editor_mode}
        key_suggestion={@drawing.key_suggestion}
      >
        <:play_controls>
          <.live_component
            module={Transport}
            id="transport"
            score={@session.score}
            ctx={@session.ctx}
            selection={@session.selection}
            engraved={@drawing.engraved}
            editor_mode={@editor_mode}
            instrument={@extras.instrument}
            lines?={@view.layout == :page}
          />
        </:play_controls>
        <:below_mode>
          <%!-- Its buttons are cells of the palette's grid, so Page and Strip
               line up under Edit and Play, the same widths. --%>
          <.live_component
            module={LayoutToggle}
            id="score-layout"
            layout={@view.layout}
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
            version_attrs={EditorSettings.version_attrs(@session, @extras)}
            dirty?={@session.dirty?}
          />
        </:trailing>
        <:below_trailing>
          <.live_component module={PaperToggle} id="score-paper-toggle" paper={@view.paper} />
        </:below_trailing>
      </.live_component>

      <.score_paper layout={@view.layout}>
        <.live_component
          module={ScoreCanvas}
          id="score-canvas"
          session={@session}
          engraved={@drawing.engraved}
          pieces={@drawing.pieces}
          geometry_json={@drawing.geometry_json}
          armed={@palette.armed}
          insert?={@palette.insert?}
          editor_mode={@editor_mode}
          layout={@view.layout}
          loading?={@drawing.loading?}
          show_note_names?={@current_scope.user.show_note_names}
        />
        <.unsaved_guard dirty?={@session.dirty?} />
        <.help_dialog shortcuts={Shortcuts.for_mode(@editor_mode)} />
        <.open_dialog
          dialog={@dialog}
          session={@session}
          scope={@current_scope}
          composition={@composition}
          version={@version}
          insert?={@palette.insert?}
          extras={@extras}
        />
        <.preferences_panel :if={@preferences?} scope={@current_scope} />
      </.score_paper>
    </Layouts.app>
    """
  end

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

  defp apply_settings(socket, key, fields) do
    case EditorSettings.apply(socket.assigns.session, fields) do
      {:ok, session} ->
        %{extras: old} = socket.assigns
        extras = %VersionExtras{tempo_text: fields.tempo_text, instrument: fields.instrument}

        socket
        |> assign(
          session: touched(session, extras, old),
          dialog: transpose_prompt(key, session.ctx)
        )
        |> assign(:extras, extras)
        |> assign_layout()

      {:error, reason} ->
        put_flash(socket, :error, error_message(reason))
    end
  end

  # Lays the score out again (`:drawing`; LiveView reserves the `layout`
  # assign).
  defp assign_layout(socket) do
    %{session: session, view: view} = socket.assigns
    lay_out(socket, session.score, layout_width(view.layout), false)
  end

  # The pieces drawn again, for a new reading-aid preference.
  defp assign_pieces(socket) do
    %{drawing: drawing, current_scope: %{user: user}, view: view} = socket.assigns
    assign(socket, :drawing, %{drawing | pieces: pieces(drawing.engraved, user, view)})
  end

  # Until the score is engraved (the static page, and the join), an empty
  # bar stands in, with a note that the score is loading.
  defp assign_placeholder(socket) do
    lay_out(socket, Score.new(), layout_width(socket.assigns.view.layout), true)
  end

  # Switching modes closes a right-click menu, but not a dialog.
  defp close_menu(%{assigns: %{dialog: {:menu, _menu}}} = socket),
    do: assign(socket, :dialog, nil)

  defp close_menu(socket), do: socket

  # Closing the Preferences panel, however it happened: back to what's
  # stored, which drops a preview that Save or Cancel didn't settle.
  defp closing_preferences(socket, true = _was_open?, false = _open?) do
    follow_user(socket, Accounts.get_user!(socket.assigns.current_scope.user.id))
  end

  defp closing_preferences(socket, _was_open?, _open?), do: socket

  # `apply_edit/2` when the outcome doesn't matter beyond the socket.
  # What the drawing depends on: the layout, and the reading aids.
  defp drawn(user, %View{layout: layout}) do
    {layout, Map.take(user, [:show_note_names, :note_names_in_edit_only, :letter_staves])}
  end

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

  # The editor in `user`'s preferences (stored or previewed); the view
  # follows a changed layout preference.
  defp follow_user(socket, user) do
    %{current_scope: scope, view: view} = socket.assigns
    new_view = View.follow(view, scope.user, user)

    socket
    |> assign(current_scope: %{scope | user: user}, view: new_view)
    |> redraw_for(drawn(scope.user, view), drawn(user, new_view))
  end

  defp history_step(session, :undo), do: Session.undo(session)
  defp history_step(session, :redo), do: Session.redo(session)

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

  defp lay_out(socket, score, width, loading?) do
    %{session: %{ctx: ctx}, extras: extras, current_scope: %{user: user}, view: view} =
      socket.assigns

    engraved = Layout.layout(score, ctx, width: width, marking: extras.tempo_text)

    # The score goes to the browser in pieces, each one finished piece of
    # SVG, not as a LiveView diff of every glyph and line: a long piece has
    # tens of thousands, and building those one by one in the browser takes
    # long enough for the connection to time out. Parsed whole, it's quick,
    # and only the pieces an edit changes are sent again.
    assign(socket, :drawing, %Drawing{
      engraved: engraved,
      pieces: pieces(engraved, user, view),
      geometry_json: Jason.encode!(EditorGeometry.encode(engraved, ctx)),
      loading?: loading?,
      key_suggestion: KeySuggestion.suggest(score, {ctx.sf, ctx.mode})
    })
  end

  # Engraving and drawing a long score takes seconds, more than joining the
  # LiveView may: the join answers with a placeholder, and the score follows
  # as an ordinary update (`handle_info(:lay_out, ...)`).
  defp lay_out_after_join(socket) do
    if connected?(socket), do: send(self(), :lay_out)
    socket
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

  defp narrow_selection_for(socket, :edit),
    do: update(socket, :session, &Session.collapse_selection/1)

  defp narrow_selection_for(socket, :play), do: socket

  # The engraving drawn, with the user's reading aids (only here: the export
  # draws the engraving without them).
  defp pieces(engraved, user, %View{layout: layout}) do
    ScoreSvg.pieces(ReadingAids.add(engraved, user), layout)
  end

  # From what was drawn to what is (`drawn/2`): a new layout lays the score
  # out again; new reading aids redraw its pieces (the aids are in them).
  # The paper and ink are CSS, so they need nothing.
  defp redraw_for(socket, same, same), do: socket
  defp redraw_for(socket, {layout, _old_aids}, {layout, _new_aids}), do: assign_pieces(socket)

  defp redraw_for(socket, _old, _new), do: assign_layout(socket)

  defp saved_and_open(socket, saved, message) do
    socket
    |> assign(:session, Session.saved(socket.assigns.session))
    |> put_flash(:info, message)
    |> push_navigate(to: version_path(saved.key.composition.id, saved.key, saved.number))
  end

  # The marking and instrument live beside the session; changing them is
  # still unsaved work.
  defp touched(session, same, same), do: session
  defp touched(session, _new, _old), do: %{session | dirty?: true}

  # A key other than the current one waits for the transpose dialog; the
  # same key closes the settings with nothing more to ask.
  defp transpose_prompt({sf, mode}, %Context{sf: sf, mode: mode}), do: nil
  defp transpose_prompt(key, _ctx), do: {:transpose, key}

  defp version_attrs(%{assigns: %{session: session, extras: extras}}) do
    EditorSettings.version_attrs(session, extras)
  end
end
