defmodule DrawMusicWeb.PaletteComponents do
  @moduledoc """
  The editor's palette: a toolbar of durations, modifiers (rest, dot,
  accidentals), connectors (tie, chords), Insert mode and undo/redo.

  Buttons show the real Bravura glyphs in score ink on score paper; the
  armed piece is drawn "picked up" (inverted and lifted). A click arms, a
  double-click locks (via the `.Palette` hook), and the armed state lives on
  the server (see `DrawMusicWeb.EditorPalette`).
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1]

  alias DrawMusic.Engraving.Smufl

  @values [
    {:whole, "Whole", "1", :noteWhole, :restWhole},
    {:half, "Half", "2", :noteHalfUp, :restHalf},
    {:quarter, "Quarter", "3", :noteQuarterUp, :restQuarter},
    {:eighth, "Eighth", "4", :note8thUp, :rest8th},
    {:sixteenth, "16th", "5", :note16thUp, :rest16th},
    {:thirty_second, "32nd", "6", :note32ndUp, :rest32nd},
    {:sixty_fourth, "64th", "7", :note64thUp, :rest64th}
  ]

  @qualities [
    {:major, "maj"},
    {:minor, "min"},
    {:diminished, "dim"},
    {:augmented, "aug"},
    {:dominant7, "7"},
    {:major7, "maj7"},
    {:minor7, "m7"},
    {:half_diminished7, "m7♭5"},
    {:diminished7, "dim7"},
    {:sus2, "sus2"},
    {:sus4, "sus4"},
    {:add9, "add9"}
  ]

  @numerals %{
    major: ~w(I ii iii IV V vi vii°),
    minor: ~w(i ii° III iv V VI vii°)
  }

  @doc "The palette toolbar."
  attr :armed, :map, default: nil
  attr :row_kind, :atom, default: :note, values: [:note, :rest]
  attr :insert?, :boolean, default: false
  attr :can_undo?, :boolean, default: false
  attr :can_redo?, :boolean, default: false
  attr :mode, :atom, default: :major, doc: "the key's mode, for chord numerals"
  attr :playing?, :boolean, default: false
  slot :trailing, doc: "extra controls at the right end (e.g. save)"

  @spec palette(map()) :: Phoenix.LiveView.Rendered.t()
  def palette(assigns) do
    assigns =
      assign(assigns,
        values: @values,
        qualities: @qualities,
        numerals: Map.fetch!(@numerals, assigns.mode)
      )

    ~H"""
    <div
      id="palette"
      phx-hook=".Palette"
      role="toolbar"
      aria-label="Palette"
      class="sticky top-0 z-20 flex flex-wrap items-center gap-2 border-b border-base-300 bg-base-100/95 px-1 py-2 backdrop-blur"
    >
      <div class="join" role="group" aria-label="Durations">
        <.piece
          :for={{value, label, key, note_glyph, rest_glyph} <- @values}
          id={"palette-#{value}"}
          event="arm"
          kind={@row_kind}
          value={value}
          title={"#{label} #{if @row_kind == :rest, do: "rest", else: "note"} (#{key})"}
          pressed={armed?(@armed, [:note, :rest], value)}
          locked={@armed && @armed.locked? && armed?(@armed, [:note, :rest], value)}
          lockable
        >
          {Smufl.char(if @row_kind == :rest, do: rest_glyph, else: note_glyph)}
        </.piece>
      </div>

      <div class="join" role="group" aria-label="Modifiers">
        <.piece
          id="palette-rest-toggle"
          event="toggle_rest"
          title="Rests instead of notes (R)"
          pressed={@row_kind == :rest}
        >
          {Smufl.char(:restQuarter)}
        </.piece>
        <.piece
          id="palette-dot"
          event="toggle_dot"
          title="Dotted (.)"
          pressed={@armed != nil and Map.get(@armed, :dots, 0) > 0}
        >
          {Smufl.char(:augmentationDot)}
        </.piece>
        <.piece
          :for={
            {id, alter, glyph, label} <- [
              {"sharp", 1, :accidentalSharp, "Sharp (hold Shift)"},
              {"flat", -1, :accidentalFlat, "Flat (hold Ctrl or Alt)"},
              {"natural", 0, :accidentalNatural, "Natural"}
            ]
          }
          id={"palette-#{id}"}
          event="set_accidental"
          alter={alter}
          title={label}
          pressed={@armed != nil and Map.get(@armed, :alter) == alter}
        >
          {Smufl.char(glyph)}
        </.piece>
      </div>

      <div class="join" role="group" aria-label="Ties and chords">
        <button
          id="palette-tie"
          type="button"
          title="Tie: drag from one note to the next (T)"
          aria-pressed={to_string(armed?(@armed, [:tie]))}
          phx-click="arm_tie"
          class={piece_class(armed?(@armed, [:tie]))}
        >
          <svg viewBox="0 0 24 12" class="h-3 w-6" aria-hidden="true">
            <path d="M2 3 Q12 12 22 3 Q12 9 2 3Z" fill="currentColor" />
          </svg>
        </button>
        <details id="palette-chords-menu" class="dropdown join-item">
          <summary
            id="palette-chords"
            aria-pressed={to_string(armed?(@armed, [:chord]))}
            title="Place a chord"
            class={[piece_class(armed?(@armed, [:chord])), "w-auto gap-1 px-3 text-sm"]}
          >
            Chords <.icon name="hero-chevron-down-micro" class="size-4 opacity-60" />
          </summary>
          <div class="dropdown-content z-30 mt-1 w-72 rounded-box border border-base-300 bg-base-100 p-3 shadow-lg">
            <p class="mb-1 text-xs opacity-60">Built on the note you click</p>
            <div class="grid grid-cols-4 gap-1">
              <button
                :for={{quality, label} <- @qualities}
                id={"palette-chord-#{quality}"}
                type="button"
                phx-click="arm_chord"
                phx-value-quality={quality}
                class={chip_class(@armed && @armed.chord == {:quality, quality})}
              >
                {label}
              </button>
            </div>
            <p class="mt-3 mb-1 text-xs opacity-60">In the key, on the octave you click</p>
            <div class="grid grid-cols-7 gap-1">
              <button
                :for={{numeral, degree} <- Enum.with_index(@numerals, 1)}
                id={"palette-degree-#{degree}"}
                type="button"
                phx-click="arm_chord"
                phx-value-degree={degree}
                class={chip_class(@armed && @armed.chord == {:degree, degree})}
              >
                {numeral}
              </button>
            </div>
          </div>
        </details>
      </div>

      <button
        id="palette-insert"
        type="button"
        title="Insert: later music on that staff moves right (Ins)"
        aria-pressed={to_string(@insert?)}
        phx-click="toggle_insert"
        class={[
          "btn btn-sm transition-colors",
          if(@insert?, do: "btn-primary", else: "btn-ghost")
        ]}
      >
        Insert
      </button>

      <button
        id="palette-play"
        type="button"
        title={
          if @playing?, do: "Stop (Space)", else: "Play from the selection, or from the start (Space)"
        }
        aria-pressed={to_string(@playing?)}
        phx-click="play"
        class={[
          "btn btn-sm gap-1 transition-colors",
          if(@playing?, do: "btn-warning", else: "btn-ghost")
        ]}
      >
        <.icon name={if @playing?, do: "hero-stop-solid", else: "hero-play-solid"} class="size-4" />
        {if @playing?, do: "Stop", else: "Play"}
      </button>

      <div class="ml-auto flex items-center gap-1">
        <button
          id="settings-button"
          type="button"
          title="Key, time signature, tempo and pickup"
          phx-click="open_settings"
          class="btn btn-ghost btn-sm btn-square"
        >
          <.icon name="hero-adjustments-horizontal" class="size-4" />
        </button>
        <button
          id="palette-undo"
          type="button"
          title="Undo (Ctrl+Z)"
          phx-click="undo"
          disabled={!@can_undo?}
          class="btn btn-ghost btn-sm btn-square"
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" />
        </button>
        <button
          id="palette-redo"
          type="button"
          title="Redo (Ctrl+Shift+Z)"
          phx-click="redo"
          disabled={!@can_redo?}
          class="btn btn-ghost btn-sm btn-square"
        >
          <.icon name="hero-arrow-uturn-right" class="size-4" />
        </button>
        {render_slot(@trailing)}
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Palette">
      export default {
        mounted() {
          this.el.addEventListener("dblclick", (e) => {
            const piece = e.target.closest("[data-lockable]")
            if (piece) this.pushEvent("lock", {kind: piece.dataset.kind, value: piece.dataset.value})
          })
        }
      }
    </script>
    """
  end

  @doc """
  Save, with a menu for Save as new version (saved versions only) and Save
  as new composition, and a dot when there are unsaved changes.
  """
  attr :dirty?, :boolean, required: true
  attr :saved?, :boolean, required: true, doc: "whether this is a stored version (not the draft)"

  @spec save_menu(map()) :: Phoenix.LiveView.Rendered.t()
  def save_menu(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <span
        :if={@dirty?}
        id="dirty-marker"
        title="Unsaved changes"
        class="size-2 rounded-full bg-warning"
        aria-label="Unsaved changes"
      />
      <div class="join">
        <button id="save" type="button" phx-click="save" class="join-item btn btn-primary btn-sm">
          Save
        </button>
        <details id="save-menu" class="dropdown dropdown-end join-item">
          <summary class="btn btn-primary btn-sm btn-square" aria-label="More ways to save">
            <.icon name="hero-chevron-down-micro" class="size-4" />
          </summary>
          <ul class="dropdown-content z-30 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 text-sm shadow-lg">
            <li :if={@saved?}>
              <button
                id="save-new-version"
                type="button"
                phx-click="save_new_version"
                class="w-full rounded px-2 py-1.5 text-left transition-colors hover:bg-base-200"
              >
                Save as new version
              </button>
            </li>
            <li>
              <button
                id="save-as"
                type="button"
                phx-click="open_save_as"
                class="w-full rounded px-2 py-1.5 text-left transition-colors hover:bg-base-200"
              >
                Save as new composition…
              </button>
            </li>
          </ul>
        </details>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :title, :string, required: true
  attr :pressed, :boolean, default: false
  attr :locked, :any, default: false
  attr :lockable, :boolean, default: false
  attr :kind, :atom, default: nil
  attr :value, :atom, default: nil
  attr :alter, :integer, default: nil
  slot :inner_block, required: true

  defp piece(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      title={@title}
      aria-label={@title}
      aria-pressed={to_string(@pressed)}
      data-kind={@kind}
      data-value={@value}
      data-lockable={@lockable}
      data-locked={@locked}
      phx-click={@event}
      phx-value-kind={@kind}
      phx-value-value={@value}
      phx-value-alter={@alter}
      class={piece_class(@pressed)}
    >
      <span class="font-['Bravura'] text-[1.6rem] leading-none" aria-hidden="true">
        {render_slot(@inner_block)}
      </span>
      <span :if={@locked} class="absolute top-0.5 right-0.5 size-1.5 rounded-full bg-primary" />
    </button>
    """
  end

  # A piece of type: score ink on score paper; picked up (inverted, lifted)
  # when armed.
  defp piece_class(pressed) do
    [
      "join-item relative grid h-10 w-10 cursor-pointer place-items-center border border-base-300",
      "transition-all duration-150 focus-visible:outline-2 focus-visible:outline-primary",
      if(pressed,
        do: "z-10 -translate-y-0.5 bg-[var(--score-ink)] text-[var(--score-paper)] shadow-md",
        else: "bg-[var(--score-paper)] text-[var(--score-ink)] hover:-translate-y-px"
      )
    ]
  end

  defp chip_class(selected) do
    [
      "rounded px-2 py-1 text-sm transition-colors",
      if(selected, do: "bg-primary text-primary-content", else: "hover:bg-base-200")
    ]
  end

  defp armed?(nil, _kinds), do: false
  defp armed?(%{kind: kind}, kinds), do: kind in kinds

  defp armed?(nil, _kinds, _value), do: false
  defp armed?(%{kind: kind, value: value}, kinds, wanted), do: kind in kinds and value == wanted
end
