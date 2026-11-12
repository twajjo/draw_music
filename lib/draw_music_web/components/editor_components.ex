defmodule DrawMusicWeb.EditorComponents do
  @moduledoc """
  Editor pieces around the score: the help dialog, and the per-bar controls
  (insert a bar before, delete the bar, add a bar at the end) laid over the
  score. The right-click menu is `DrawMusicWeb.Editor.NoteMenu`.
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  alias DrawMusicWeb.{
    BarControl,
    HelpComponents,
    ScoreComponents
  }

  # Bar controls sit this far above a system's top line (staff spaces).
  @controls_raise 2.2

  @doc """
  The cheat-sheet over the score, the current mode's groups first. It is
  always on the page, hidden: opening and closing it are browser-only JS
  commands (`show_help/1`, `hide_help/1`), with no trip to the server. The
  `?` key runs the command in `data-show`.
  """
  attr :shortcuts, :list, required: true

  @spec help_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def help_dialog(assigns) do
    ~H"""
    <div
      id="help"
      class="fixed inset-0 z-50 place-items-center bg-black/40 p-4"
      style="display: none"
      data-show={show_help()}
    >
      <div
        id="help-dialog"
        role="dialog"
        aria-label="Keys and mouse"
        class="max-h-[85vh] w-full max-w-3xl overflow-y-auto rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away={hide_help()}
        phx-window-keydown={hide_help()}
        phx-key="Escape"
      >
        <div class="mb-4 flex items-center justify-between">
          <p class="text-lg font-semibold">Keys and mouse</p>
          <button
            id="help-close"
            type="button"
            phx-click={hide_help()}
            class="btn btn-ghost btn-sm btn-square"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <HelpComponents.cheat_sheet shortcuts={@shortcuts} />
      </div>
    </div>
    """
  end

  @doc "Hides the help dialog, in the browser."
  @spec hide_help(JS.t()) :: JS.t()
  def hide_help(js \\ %JS{}), do: JS.hide(js, to: "#help")

  @doc "Shows the help dialog, in the browser."
  @spec show_help(JS.t()) :: JS.t()
  def show_help(js \\ %JS{}), do: JS.show(js, to: "#help", display: "grid")

  @doc """
  Small ⊕/⊖ buttons at each bar's top-left (insert a bar before it, delete
  it) and an add-bar button after the last bar, positioned in percent of
  the score's box so they follow both layouts.
  """
  attr :engraved, :map, required: true
  attr :score, :map, required: true, doc: "the Music.Score, to know which bars hold music"

  @spec measure_controls(map()) :: Phoenix.LiveView.Rendered.t()
  def measure_controls(assigns) do
    padding = ScoreComponents.padding()
    total = assigns.engraved.width + 2 * padding

    bars =
      for system <- assigns.engraved.systems, m <- system.measures do
        %BarControl{
          index: m.index,
          left: percent(m.x + padding, total),
          top: percent(max(system.y - @controls_raise, 0), assigns.engraved.height),
          end_left: percent(m.x + m.width + padding, total)
        }
      end

    assigns =
      assign(assigns, bars: bars, last: List.last(bars), filled: filled_bars(assigns.score))

    ~H"""
    <div id="measure-controls" class="pointer-events-none absolute inset-0">
      <div
        :for={bar <- @bars}
        class="pointer-events-auto absolute flex -translate-y-1/2 gap-0.5 opacity-25 transition-opacity hover:opacity-100 focus-within:opacity-100"
        style={"left: #{bar.left}%; top: #{bar.top}%"}
      >
        <button
          id={"measure-#{bar.index}-insert"}
          type="button"
          title="Insert a bar before this one"
          aria-label="Insert a bar before this one"
          phx-click="insert_measure"
          phx-value-index={bar.index}
          class="btn btn-ghost btn-xs btn-square"
        >
          <.icon name="hero-plus-circle-mini" class="size-4" />
        </button>
        <button
          id={"measure-#{bar.index}-delete"}
          type="button"
          title="Delete this bar"
          aria-label="Delete this bar"
          phx-click="delete_measure"
          phx-value-index={bar.index}
          data-confirm={MapSet.member?(@filled, bar.index) && "Delete this bar and the music in it?"}
          class="btn btn-ghost btn-xs btn-square"
        >
          <.icon name="hero-minus-circle-mini" class="size-4" />
        </button>
      </div>
      <button
        id="add-measure"
        type="button"
        title="Add a bar at the end"
        phx-click="add_measure"
        class="btn btn-ghost btn-xs pointer-events-auto absolute -translate-y-1/2 gap-1 opacity-60 transition-opacity hover:opacity-100"
        style={"left: calc(#{@last.end_left}% + 0.5rem); top: #{@last.top}%"}
      >
        <.icon name="hero-plus-mini" class="size-4" /> Bar
      </button>
    </div>
    """
  end

  defp percent(part, whole), do: part / whole * 100

  defp filled_bars(score) do
    for {m, i} <- Enum.with_index(score.measures),
        m.notes != [] or Enum.any?(m.rests, &(not &1.filler)),
        into: MapSet.new() do
      i
    end
  end
end
