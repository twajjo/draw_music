defmodule DrawMusicWeb.EditorPage do
  @moduledoc """
  The parts of the editor's page that `DrawMusicWeb.EditorLive` lays out:
  the header above the palette, the paper the score sits on, and whichever
  dialog or menu is open. None has events of its own: the dialogs are
  LiveComponents that handle theirs.
  """

  use DrawMusicWeb, :html

  import DrawMusicWeb.LibraryComponents,
    only: [credits: 1, details_button: 1, version_picker: 1, version_path: 3]

  alias DrawMusic.Samples
  alias DrawMusicWeb.{DetailsDialog, EditorSettings}

  alias DrawMusicWeb.Editor.{
    NoteMenu,
    SaveAsDialog,
    SettingsDialog,
    TempoDialog,
    TransposeDialog
  }

  attr :composition, :map, required: true
  attr :version, :map, required: true, doc: "the version open; a draft's `id` is nil"

  attr :instrument, :integer,
    required: true,
    doc: "the version's instrument (a GM program), as set in Score settings"

  @doc """
  The title row: the composition's name, the details button and what the
  version is for (its instrument: shown only, changed in Score settings),
  then the subtitle and credits; at the right the version picker, or
  "Unsaved" for a draft, and the downloads.
  """
  @spec editor_header(map()) :: Phoenix.LiveView.Rendered.t()
  def editor_header(assigns) do
    ~H"""
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div class="space-y-1">
        <div class="flex flex-wrap items-center gap-2">
          <h1 id="composition-name" class="text-2xl font-semibold">{@composition.name}</h1>
          <.details_button id="edit-details" />
          <span id="version-instrument" class="ml-4 text-sm opacity-70">
            For {Samples.instrument!(@instrument).name}
          </span>
        </div>
        <p :if={@composition.subtitle} class="opacity-80">{@composition.subtitle}</p>
        <p :if={credits(@composition) != ""} class="text-sm opacity-60">{credits(@composition)}</p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <%= if @version.id do %>
          <.version_picker id="version-picker" composition={@composition} version={@version} />
          <.downloads version={@version} />
        <% else %>
          <span id="unsaved" class="badge badge-ghost">Unsaved</span>
        <% end %>
      </div>
    </header>
    """
  end

  attr :dialog, :any, required: true, doc: "EditorLive's `@dialog`: what is open, or nil"
  attr :session, :map, required: true, doc: "the `DrawMusic.Music.Session`"
  attr :scope, :map, required: true
  attr :composition, :map, required: true
  attr :version, :map, required: true
  attr :insert?, :boolean, required: true
  attr :extras, :map, required: true, doc: "the `DrawMusicWeb.Editor.VersionExtras`"

  @doc """
  The one dialog (or the right-click menu) that is open, if any: at most
  one is open at a time.
  """
  @spec open_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def open_dialog(%{dialog: {:menu, menu}} = assigns) do
    assigns = assign(assigns, :menu, menu)

    ~H"""
    <.live_component
      module={NoteMenu}
      id="note-menu"
      menu={@menu}
      insert?={@insert?}
      score={@session.score}
      ctx={@session.ctx}
    />
    """
  end

  # A saved composition's details are stored at once (they aren't part of
  # the score, so not of its undo or its unsaved changes); a draft's are
  # kept until its first save.
  def open_dialog(%{dialog: :details} = assigns) do
    ~H"""
    <.live_component
      module={DetailsDialog}
      id="details"
      scope={@scope}
      composition={@composition}
      persist?={@version.id != nil}
    />
    """
  end

  def open_dialog(%{dialog: :save_as} = assigns) do
    ~H"""
    <.live_component
      module={SaveAsDialog}
      id="save-as"
      scope={@scope}
      composition={@composition}
      version={@version}
      key={%{sf: @session.ctx.sf, mode: @session.ctx.mode}}
      version_attrs={EditorSettings.version_attrs(@session, @extras)}
    />
    """
  end

  def open_dialog(%{dialog: :settings} = assigns) do
    ~H"""
    <.live_component
      module={SettingsDialog}
      id="settings"
      ctx={@session.ctx}
      tempo_text={@extras.tempo_text}
      instrument={@extras.instrument}
    />
    """
  end

  def open_dialog(%{dialog: {:tempo, target}} = assigns) do
    assigns = assign(assigns, :target, target)

    ~H"""
    <.live_component module={TempoDialog} id="tempo" target={@target} ctx={@session.ctx} />
    """
  end

  def open_dialog(%{dialog: {:transpose, key}} = assigns) do
    assigns = assign(assigns, :key, key)

    ~H"""
    <.live_component module={TransposeDialog} id="transpose" key={@key} />
    """
  end

  def open_dialog(assigns) do
    ~H""
  end

  attr :layout, :atom, required: true, doc: "`:page` or `:strip` (which scrolls sideways)"
  slot :inner_block, required: true
  @doc "The paper the score, and the dialogs over it, sit on."
  @spec score_paper(map()) :: Phoenix.LiveView.Rendered.t()
  def score_paper(assigns) do
    ~H"""
    <div
      id="score-paper"
      class={[
        "rounded-box border border-base-300 p-4 shadow-sm transition-colors",
        if(@layout == :strip, do: "overflow-x-auto")
      ]}
      style="background-color: var(--score-paper)"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :version, :map, required: true
  # The saved version's SVG and MIDI downloads.
  defp downloads(assigns) do
    ~H"""
    <.button id="download-svg" href={export_path(@version, "svg")} download class="btn btn-sm">
      <.icon name="hero-arrow-down-tray" class="size-4" /> SVG
    </.button>
    <.button id="download-mid" href={export_path(@version, "mid")} download class="btn btn-sm">
      <.icon name="hero-arrow-down-tray" class="size-4" /> MIDI
    </.button>
    """
  end

  defp export_path(version, extension) do
    version_path(version.key.composition.id, version.key, version.number) <> "/score.#{extension}"
  end
end
