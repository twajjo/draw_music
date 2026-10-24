defmodule DrawMusicWeb.EditorComponents do
  @moduledoc """
  Editor pieces around the score: the right-click menu for a note or rest,
  and the per-bar controls (insert a bar before, delete the bar, add a bar
  at the end) laid over the score.
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1, input: 1]

  alias DrawMusic.Engraving.Smufl
  alias DrawMusicWeb.{BarControl, HelpComponents, LibraryComponents, ScoreComponents}

  # Bar controls sit this far above a system's top line (staff spaces).
  @controls_raise 2.2

  @lengths [
    {:whole, :noteWhole, "Whole"},
    {:half, :noteHalfUp, "Half"},
    {:quarter, :noteQuarterUp, "Quarter"},
    {:eighth, :note8thUp, "Eighth"},
    {:sixteenth, :note16thUp, "16th"},
    {:thirty_second, :note32ndUp, "32nd"},
    {:sixty_fourth, :note64thUp, "64th"}
  ]

  @doc "Asks for the new composition's name (and credits) when saving as a new composition."
  attr :form, Phoenix.HTML.Form, required: true

  @spec save_as_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def save_as_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        class="w-full max-w-md rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close_save_as"
        phx-window-keydown="close_save_as"
        phx-key="Escape"
      >
        <h2 class="text-lg font-semibold">Save as a new composition</h2>
        <.form
          for={@form}
          id="save-as-form"
          phx-change="validate_save_as"
          phx-submit="save_as"
          class="mt-4 space-y-2"
        >
          <.input field={@form[:name]} label="Name" required phx-debounce="300" autofocus />
          <.input field={@form[:composer]} label="Composer" />
          <div class="flex justify-end gap-2 pt-2">
            <button type="button" phx-click="close_save_as" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">Save</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @doc "The cheat-sheet over the score, the current mode's groups first."
  attr :shortcuts, :list, required: true

  @spec help_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def help_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        id="help-dialog"
        role="dialog"
        aria-label="Keys and mouse"
        class="max-h-[85vh] w-full max-w-3xl overflow-y-auto rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close_help"
        phx-window-keydown="close_help"
        phx-key="Escape"
      >
        <div class="mb-4 flex items-center justify-between">
          <p class="text-lg font-semibold">Keys and mouse</p>
          <button
            id="help-close"
            type="button"
            phx-click="close_help"
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

  @doc "The score's settings: key, time signature, tempo and pickup."
  attr :form, Phoenix.HTML.Form, required: true

  @spec settings_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def settings_panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        class="w-full max-w-lg rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close_settings"
        phx-window-keydown="close_settings"
        phx-key="Escape"
      >
        <h2 class="text-lg font-semibold">Score settings</h2>
        <.form
          for={@form}
          id="settings-form"
          phx-submit="apply_settings"
          class="mt-4 grid gap-x-4 sm:grid-cols-2"
        >
          <LibraryComponents.score_settings_fields form={@form} />
          <div class="flex justify-end gap-2 pt-2 sm:col-span-2">
            <button type="button" phx-click="close_settings" class="btn btn-ghost">Cancel</button>
            <button type="submit" class="btn btn-primary">Apply</button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @doc "Asks how to move the notes into a newly chosen key."
  attr :key_name, :string, required: true

  @spec transpose_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def transpose_dialog(assigns) do
    ~H"""
    <div id="transpose-dialog" class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div class="w-full max-w-sm rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl">
        <h2 class="text-lg font-semibold">Transpose to {@key_name}?</h2>
        <p class="mt-1 text-sm opacity-70">The notes move with the key.</p>
        <div class="mt-4 flex flex-wrap gap-2">
          <button
            :for={{dir, label} <- [{"nearest", "Nearest"}, {"up", "Up"}, {"down", "Down"}]}
            id={"transpose-#{dir}"}
            type="button"
            phx-click="transpose_key"
            phx-value-direction={dir}
            class={["btn", if(dir == "nearest", do: "btn-primary", else: "btn-ghost")]}
          >
            {label}
          </button>
          <button type="button" phx-click="cancel_transpose" class="btn btn-ghost ml-auto">Cancel</button>
        </div>
      </div>
    </div>
    """
  end

  @intervals ~w(m2 M2 m3 M3 P4 A4 P5 m6 M6 m7 M7 P8)

  @doc """
  The right-click menu, at the pointer: for a selection (`kind: :selection`)
  or for one note or rest.
  """
  attr :menu, :map, required: true, doc: "%{id, ids, kind: :note | :rest | :selection, x, y}"

  @spec context_menu(map()) :: Phoenix.LiveView.Rendered.t()
  def context_menu(%{menu: %{kind: :selection}} = assigns) do
    assigns = assign(assigns, :intervals, @intervals)

    ~H"""
    <div
      id="context-menu"
      role="menu"
      phx-click-away="close_menu"
      phx-window-keydown="close_menu"
      phx-key="Escape"
      class="fixed z-40 w-64 rounded-box border border-base-300 bg-base-100 p-2 text-sm shadow-xl"
      style={"left: #{@menu.x}px; top: #{@menu.y}px"}
    >
      <p class="px-2 pb-1 text-xs opacity-60">
        {length(@menu.ids)} selected
      </p>
      <p class="px-2 pt-1 pb-1 text-xs opacity-60">Transpose</p>
      <div class="grid grid-cols-2 gap-1 px-1">
        <.transpose_button
          :for={{by, label} <- [{"step", "Step"}, {"semitone", "Semitone"}, {"octave", "Octave"}]}
          by={by}
          label={label}
        />
      </div>
      <details class="px-1 pt-1">
        <summary class="cursor-pointer rounded px-1 py-1 transition-colors hover:bg-base-200">
          By interval…
        </summary>
        <div class="grid grid-cols-4 gap-1 pt-1">
          <%= for interval <- @intervals, dir <- ["up", "down"] do %>
            <button
              id={"menu-interval-#{interval_slug(interval)}-#{dir}"}
              type="button"
              phx-click="transpose"
              phx-value-by="interval"
              phx-value-interval={interval}
              phx-value-dir={dir}
              class="rounded px-1 py-1 transition-colors hover:bg-base-200"
            >
              {interval} {if dir == "up", do: "↑", else: "↓"}
            </button>
          <% end %>
        </div>
      </details>
      <div class="my-1 border-t border-base-300" />
      <.item id="menu-reverse" event="reverse">Reverse</.item>
      <.item id="menu-copy" event="menu_copy">Copy</.item>
      <.item id="menu-cut" event="menu_cut">Cut</.item>
      <div class="my-1 border-t border-base-300" />
      <.item id="menu-delete" event="menu_delete" danger>Delete</.item>
    </div>
    """
  end

  def context_menu(assigns) do
    assigns = assign(assigns, :lengths, @lengths)

    ~H"""
    <div
      id="context-menu"
      role="menu"
      phx-click-away="close_menu"
      phx-window-keydown="close_menu"
      phx-key="Escape"
      class="fixed z-40 w-60 rounded-box border border-base-300 bg-base-100 p-2 text-sm shadow-xl"
      style={"left: #{@menu.x}px; top: #{@menu.y}px"}
    >
      <.item id="menu-split" event="split">Split in two</.item>
      <p class="px-2 pt-2 pb-1 text-xs opacity-60">Length</p>
      <div class="flex flex-wrap gap-1 px-1 pb-1">
        <button
          :for={{value, glyph, label} <- @lengths}
          id={"menu-length-#{value}"}
          type="button"
          title={label}
          aria-label={label}
          phx-click="set_value"
          phx-value-value={value}
          class="grid h-8 w-7 place-items-center rounded transition-colors hover:bg-base-200"
        >
          <span class="font-['Bravura'] text-xl leading-none">{Smufl.char(glyph)}</span>
        </button>
        <button
          id="menu-length-dot"
          type="button"
          title="Dotted"
          aria-label="Dotted"
          phx-click="toggle_menu_dot"
          class="grid h-8 w-7 place-items-center rounded transition-colors hover:bg-base-200"
        >
          <span class="font-['Bravura'] text-xl leading-none">{Smufl.char(:augmentationDot)}</span>
        </button>
      </div>
      <div class="my-1 border-t border-base-300" />
      <%= if @menu.kind == :note do %>
        <.item id="menu-to-rest" event="to_rest">Make it a rest</.item>
        <.item id="menu-tie-next" event="tie_next">Tie to the next note</.item>
        <.item id="menu-untie" event="untie">Remove ties</.item>
      <% else %>
        <.item id="menu-to-note" event="to_note">Make it a note here</.item>
      <% end %>
      <div class="my-1 border-t border-base-300" />
      <.item id="menu-delete" event="menu_delete" danger>Delete</.item>
    </div>
    """
  end

  # DOM ids must not differ only by case (m3 vs M3).
  defp interval_slug("m" <> n), do: "min" <> n
  defp interval_slug("M" <> n), do: "maj" <> n
  defp interval_slug("P" <> n), do: "p" <> n
  defp interval_slug("A" <> n), do: "aug" <> n

  attr :by, :string, required: true
  attr :label, :string, required: true

  defp transpose_button(assigns) do
    ~H"""
    <%= for dir <- ["up", "down"] do %>
      <button
        id={"menu-transpose-#{@by}-#{dir}"}
        type="button"
        phx-click="transpose"
        phx-value-by={@by}
        phx-value-dir={dir}
        class="rounded px-2 py-1 text-left transition-colors hover:bg-base-200"
      >
        {@label} {if dir == "up", do: "up", else: "down"}
      </button>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :danger, :boolean, default: false
  slot :inner_block, required: true

  defp item(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      role="menuitem"
      phx-click={@event}
      class={[
        "block w-full rounded px-2 py-1.5 text-left transition-colors hover:bg-base-200",
        @danger && "text-error"
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

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
        m.notes != [] or m.rests != [],
        into: MapSet.new() do
      i
    end
  end
end
