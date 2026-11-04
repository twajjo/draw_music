defmodule DrawMusicWeb.HelpComponents do
  @moduledoc """
  The cheat-sheet: every key and mouse action (`DrawMusicWeb.Shortcuts`) by
  group, with small diagrams of the gestures, drawn in the score's own ink
  and paper colours and its music font.
  """

  use Phoenix.Component

  alias DrawMusic.Engraving.Smufl
  alias DrawMusicWeb.Shortcut

  @key_labels %{
    "ArrowUp" => "↑",
    "ArrowDown" => "↓",
    "ArrowLeft" => "←",
    "ArrowRight" => "→",
    "Escape" => "Esc",
    "Insert" => "Ins",
    "Delete" => "Del"
  }

  # Diagram geometry, in staff spaces (Bravura: one em is four spaces).
  @font_size 4
  @staff_lines 0..4
  @staff_width 16

  @doc "Shortcuts in groups, in the order given."
  attr :shortcuts, :list, required: true, doc: "`DrawMusicWeb.Shortcut` structs, grouped"

  @spec cheat_sheet(map()) :: Phoenix.LiveView.Rendered.t()
  def cheat_sheet(assigns) do
    assigns = assign(assigns, :groups, Enum.chunk_by(assigns.shortcuts, & &1.group))

    ~H"""
    <div class="score-colors space-y-8">
      <section :for={[%{group: group} | _] = shortcuts <- @groups} class="space-y-3">
        <h2 class="text-lg font-semibold">{group}</h2>
        <dl class="grid grid-cols-[minmax(8rem,auto)_1fr] gap-x-6 gap-y-3">
          <%= for shortcut <- shortcuts do %>
            <dt class="flex flex-wrap items-start gap-1 text-sm">
              <.how shortcut={shortcut} />
            </dt>
            <dd class="space-y-2 text-sm">
              <p>
                {shortcut.action}
                <span :if={shortcut.modes == [:play]} class="badge badge-ghost badge-sm">Play mode</span>
              </p>
              <.diagram :if={shortcut.diagram} name={shortcut.diagram} />
            </dd>
          <% end %>
        </dl>
      </section>
    </div>
    """
  end

  attr :shortcut, Shortcut, required: true

  defp how(%{shortcut: %Shortcut{keys: []}} = assigns) do
    ~H"""
    <span class="italic opacity-80">{@shortcut.mouse}</span>
    """
  end

  defp how(assigns) do
    ~H"""
    <kbd :for={key <- @shortcut.keys} class="kbd kbd-sm">{key_label(key)}</kbd>
    """
  end

  defp key_label(key) do
    key
    |> String.split("+")
    |> Enum.map_join("+", &Map.get(@key_labels, &1, &1))
  end

  @doc "One gesture's picture, by name (see `DrawMusicWeb.Shortcut`'s `:diagram`)."
  attr :name, :atom, required: true

  @spec diagram(map()) :: Phoenix.LiveView.Rendered.t()
  def diagram(assigns) do
    assigns =
      assign(assigns,
        id: "diagram-#{String.replace(Atom.to_string(assigns.name), "_", "-")}",
        lines: @staff_lines,
        width: @staff_width,
        font_size: @font_size,
        note: Smufl.char(:noteQuarterUp),
        sharp: Smufl.char(:accidentalSharp),
        flat: Smufl.char(:accidentalFlat)
      )

    ~H"""
    <svg
      id={@id}
      viewBox={"-1 -3 #{@width + 2} 10"}
      class="h-16 w-auto rounded border border-base-300"
      style="background-color: var(--score-paper); color: var(--score-ink)"
      role="img"
      aria-hidden="true"
    >
      <line
        :for={y <- @lines}
        x1="0"
        x2={@width}
        y1={y}
        y2={y}
        stroke="currentColor"
        stroke-width="0.12"
      />
      <g fill="currentColor" font-family="Bravura" font-size={@font_size}>
        <.picture name={@name} note={@note} sharp={@sharp} flat={@flat} />
      </g>
    </svg>
    """
  end

  attr :name, :atom, required: true
  attr :note, :string, required: true
  attr :sharp, :string, required: true
  attr :flat, :string, required: true

  defp picture(%{name: :ghost_snap} = assigns) do
    ~H"""
    <text x="3" y="2">{@note}</text>
    <text x="9" y="1.5" opacity="0.45">{@note}</text>
    <path d="M13 0.2 l1.6 1.2 -0.8 0.1 0.5 1 -0.4 0.2 -0.5 -1 -0.5 0.5z" />
    """
  end

  defp picture(%{name: :accidental_modifiers} = assigns) do
    ~H"""
    <text x="2" y="2.5">{@sharp}</text>
    <text x="3.4" y="2.5">{@note}</text>
    <text x="9" y="2.5">{@flat}</text>
    <text x="10.2" y="2.5">{@note}</text>
    <text x="2" y="6.6" font-family="sans-serif" font-size="1.4">Shift</text>
    <text x="9" y="6.6" font-family="sans-serif" font-size="1.4">Ctrl</text>
    """
  end

  defp picture(%{name: :tie_drag} = assigns) do
    ~H"""
    <text x="3" y="3">{@note}</text>
    <text x="10" y="3">{@note}</text>
    <path d="M4.2 3.6 Q7.6 5.4 11 3.6 Q7.6 4.8 4.2 3.6Z" />
    <line
      x1="4"
      y1="3"
      x2="10.6"
      y2="3"
      stroke="var(--score-selection)"
      stroke-width="0.2"
      stroke-dasharray="0.5 0.3"
    />
    """
  end

  defp picture(%{name: :rubber_band} = assigns) do
    ~H"""
    <text x="2" y="3">{@note}</text>
    <text x="6" y="2">{@note}</text>
    <text x="10" y="1">{@note}</text>
    <rect
      x="5"
      y="-2.5"
      width="7.5"
      height="6.5"
      fill="var(--score-selection)"
      fill-opacity="0.15"
      stroke="var(--score-selection)"
      stroke-width="0.1"
    />
    """
  end

  defp picture(%{name: :insert_shift} = assigns) do
    ~H"""
    <text x="2" y="2">{@note}</text>
    <text x="5.5" y="1" fill="var(--score-selection)">{@note}</text>
    <text x="11" y="3" opacity="0.45">{@note}</text>
    <path
      d="M8 5.6 h3.5 M10.6 4.9 l1 0.7 -1 0.7"
      stroke="currentColor"
      stroke-width="0.2"
      fill="none"
    />
    """
  end

  defp picture(%{name: :play_cursor} = assigns) do
    ~H"""
    <text x="3" y="2">{@note}</text>
    <text x="7" y="2" fill="var(--color-warning)">{@note}</text>
    <path d="M10 -1.4h1l1.4 -1.1v3.8l-1.4 -1.1h-1z" />
    <path d="M13.2 -1.6a1.6 1.6 0 0 1 0 2.2" stroke="currentColor" stroke-width="0.2" fill="none" />
    """
  end

  defp picture(%{name: :range_playback} = assigns) do
    ~H"""
    <text x="1.5" y="3">{@note}</text>
    <text x="5.5" y="2" fill="var(--color-warning)">{@note}</text>
    <text x="9" y="1" fill="var(--color-warning)">{@note}</text>
    <text x="13" y="2">{@note}</text>
    <rect
      x="4.8"
      y="-2.5"
      width="7"
      height="6.5"
      fill="var(--score-selection)"
      fill-opacity="0.15"
      stroke="var(--score-selection)"
      stroke-width="0.1"
    />
    """
  end

  defp picture(%{name: :loop} = assigns) do
    ~H"""
    <text x="3" y="2">{@note}</text>
    <text x="8" y="1">{@note}</text>
    <path
      d="M3 5.6 H11.5 M11.5 5.6 v-0.8 M3 5.6 v-0.8 M10.9 6.2 l0.6 -0.6 -0.6 -0.6"
      stroke="currentColor"
      stroke-width="0.2"
      fill="none"
    />
    """
  end
end
