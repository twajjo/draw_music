defmodule DrawMusicWeb.EditorLive do
  @moduledoc """
  A score, in the user's preferred layout: one long staff or page-style
  systems. `:show` opens a saved version; `:new` (the main page) starts a
  blank, unsaved composition: C major, 4/4, four empty measures. Read-only
  for now; editing and saving arrive in Phase 4.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.{LibraryComponents, ScoreComponents, SettingsComponents}

  alias DrawMusic.Engraving.Layout
  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.{Context, Score}
  alias DrawMusicWeb.{ScorePreferences, VersionLookup}

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
            href={svg_path(@version)}
            download
            class="btn btn-sm"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> SVG
          </.button>
        </div>
      </header>

      <div
        id="score-paper"
        class={[
          "rounded-box border border-base-300 p-4 shadow-sm transition-colors",
          if(@current_scope.user.score_layout == :strip, do: "overflow-x-auto")
        ]}
        style="background-color: var(--score-paper)"
      >
        <.score
          id="score"
          layout={@engraved}
          class={if(@current_scope.user.score_layout == :page, do: "mx-auto h-auto w-full max-w-5xl")}
        />
      </div>
    </Layouts.app>
    """
  end

  @draft_measures 4

  @impl true
  def mount(params, _session, socket) do
    {composition, version, title} =
      load(socket.assigns.live_action, socket.assigns.current_scope, params)

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:composition, composition)
     |> assign(:version, version)
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

  @impl true
  def handle_event("set_score_layout" = event, params, socket) do
    {:noreply, event |> ScorePreferences.apply_event(params, socket) |> assign_layout()}
  end

  # `:engraved`, not `:layout`: LiveView reserves the `layout` assign.
  defp assign_layout(socket) do
    %{version: version, current_scope: scope} = socket.assigns
    width = layout_width(scope.user.score_layout)

    assign(
      socket,
      :engraved,
      Layout.layout(version.score, Context.from_version(version), width: width)
    )
  end

  defp svg_path(version),
    do: version_path(version.key.composition.id, version.key, version.number) <> "/score.svg"
end
