defmodule DrawMusicWeb.EditorLive do
  @moduledoc """
  The score editor, in the user's preferred layout (one long staff or
  page-style systems) to start with; the palette switches it for the
  session (`DrawMusicWeb.Editor.View`). `:show` opens a saved version;
  `:new` (the main page) starts a blank, unsaved composition
  (`DrawMusicWeb.VersionLookup.open/3`). The score is drawn by
  `DrawMusicWeb.Editor.Drawing`; a refused edit's message comes from
  `DrawMusicWeb.Editor.Messages`.

  The score lives in a `DrawMusic.Music.Session` (selection, clipboard,
  undo/redo, unsaved changes); the palette state (armed item, note/rest
  row, Insert mode) is kept beside it. Every edit goes through
  `DrawMusicWeb.EditorLive.Edit`; the edits themselves are built by
  `DrawMusicWeb.EditorCommands` and `DrawMusicWeb.EditorPlacement`.

  The components report their results as messages. This module takes the
  editing ones; two `:handle_info` hooks take the rest first:
  `DrawMusicWeb.EditorLive.ViewChanges` (Page / Strip, Sheet, the
  Preferences form) and `DrawMusicWeb.EditorLive.Versions` (Score
  settings, the key, the instrument, saving).
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.{EditorComponents, EditorPage}
  import DrawMusicWeb.PreferencesComponents, only: [preferences_panel: 1]

  alias DrawMusic.Accounts
  alias DrawMusic.Music.{Context, Session}

  alias DrawMusicWeb.{
    DetailsDialog,
    EditorPalette,
    EditorSettings,
    LayoutToggle,
    PaperToggle,
    Shortcuts,
    VersionLookup
  }

  alias DrawMusicWeb.Editor.{
    Palette,
    PaletteState,
    SaveMenu,
    ScoreCanvas,
    Transport,
    VersionExtras,
    View
  }

  alias DrawMusicWeb.EditorLive.{Edit, Versions, ViewChanges}

  @impl true
  def handle_event("edit_details", _params, socket) do
    {:noreply, assign(socket, :dialog, :details)}
  end

  # Events from the browser that don't fit the current state (a menu action
  # with no menu open, malformed params) are ignored rather than crashing
  # the editor. Keep this clause last.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:lay_out, socket), do: {:noreply, Edit.assign_layout(socket)}

  # The details dialog's results (see `DrawMusicWeb.DetailsDialog`).
  def handle_info({DetailsDialog, {:saved, composition}}, socket) do
    {:noreply,
     socket
     |> assign(composition: composition, page_title: composition.name, dialog: nil)
     |> put_flash(:info, "Details saved.")}
  end

  def handle_info({DetailsDialog, :closed}, socket), do: {:noreply, assign(socket, :dialog, nil)}

  # The editor components' results (see `DrawMusicWeb.Editor.Intent`); the
  # settings, key, instrument and saving ones go to `EditorLive.Versions`.
  # Play mode doesn't edit the score, step through its history or arm the
  # palette.
  def handle_info({:editor, intent}, %{assigns: %{editor_mode: :play}} = socket)
      when is_tuple(intent) and elem(intent, 0) in [:edit, :history, :palette] do
    {:noreply, socket}
  end

  def handle_info({:editor, :close}, socket), do: {:noreply, assign(socket, :dialog, nil)}

  def handle_info({:editor, {:edit, fun}}, socket), do: {:noreply, Edit.edit(socket, fun)}

  def handle_info({:editor, {:session, fun}}, socket) do
    {:noreply, update(socket, :session, fun)}
  end

  def handle_info({:editor, {:edit, fun, :follow}}, socket) do
    {:noreply, Edit.edit_and_follow(socket, fun)}
  end

  def handle_info({:editor, {:edit, fun, :select}}, socket) do
    {:noreply, Edit.edit_and_select(socket, fun)}
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
     |> Edit.assign_layout()}
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
      VersionLookup.open(socket.assigns.live_action, socket.assigns.current_scope, params)

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
     |> Edit.assign_placeholder()
     |> lay_out_after_join()
     # Hooks taking some components' results before `handle_info/2`: the
     # view (Page / Strip, Sheet, the Preferences form), then the version
     # (settings, key, instrument, saving).
     |> ViewChanges.attach()
     |> Versions.attach()}
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
        beat={EditorPalette.beat(@session.ctx)}
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

  # Switching modes closes a right-click menu, but not a dialog.
  defp close_menu(%{assigns: %{dialog: {:menu, _menu}}} = socket),
    do: assign(socket, :dialog, nil)

  defp close_menu(socket), do: socket

  # Closing the Preferences panel, however it happened: back to what's
  # stored, which drops a preview that Save or Cancel didn't settle.
  defp closing_preferences(socket, true = _was_open?, false = _open?) do
    ViewChanges.follow_user(socket, Accounts.get_user!(socket.assigns.current_scope.user.id))
  end

  defp closing_preferences(socket, _was_open?, _open?), do: socket

  defp history_step(session, :undo), do: Session.undo(session)
  defp history_step(session, :redo), do: Session.redo(session)

  # Engraving and drawing a long score takes seconds, more than joining the
  # LiveView may: the join answers with a placeholder, and the score follows
  # as an ordinary update (`handle_info(:lay_out, ...)`).
  defp lay_out_after_join(socket) do
    if connected?(socket), do: send(self(), :lay_out)
    socket
  end

  defp narrow_selection_for(socket, :edit),
    do: update(socket, :session, &Session.collapse_selection/1)

  defp narrow_selection_for(socket, :play), do: socket
end
