defmodule DrawMusicWeb.PaletteComponents do
  @moduledoc """
  The editor's toolbar, two rows tall: the Edit/Play switch over the score
  layout on the left, help and save at the top right. In Edit mode the
  middle holds the edit palette: durations and connectors (tie, chords) on
  the first row; modifiers (rest, dot, accidentals), the Overlay/Insert
  toggle, settings and undo/redo on the second. In Play mode it holds the
  play controls instead: Rewind, Play/Pause and Loop, then the playback
  instrument.

  Buttons show the real Bravura glyphs in score ink on score paper; the
  armed piece is drawn "picked up" (inverted and lifted). A click arms it,
  and it stays armed until another is picked; the armed state lives on the
  server (see `DrawMusicWeb.EditorPalette`).
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1, input: 1]

  alias DrawMusic.Engraving.Smufl
  alias DrawMusic.Music.Chords

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
    :major,
    :minor,
    :diminished,
    :augmented,
    :dominant7,
    :major7,
    :minor7,
    :half_diminished7,
    :diminished7,
    :sus2,
    :sus4,
    :add9
  ]

  @note_glyphs for {_value, _label, _key, note_glyph, _rest} <- @values, do: note_glyph
  # SMuFL y (up) from the lowest notehead's bottom to the 64th's flag tip.
  @note_range {-0.6, 4.9}
  # Staff spaces around each glyph, and rem per staff space.
  @glyph_pad 0.2
  @glyph_rem 0.34

  @doc """
  The editor's toolbar: the Edit/Play switch, then the palette for the
  current mode (the edit palette, or the play controls), then help and
  `:trailing` (save) in both.
  """
  attr :armed, :map, default: nil
  attr :row_kind, :atom, default: :note, values: [:note, :rest]
  attr :insert?, :boolean, default: false
  attr :can_undo?, :boolean, default: false
  attr :can_redo?, :boolean, default: false
  attr :mode, :atom, default: :major, doc: "the key's mode, for chord numerals"
  attr :editor_mode, :atom, default: :edit, values: [:edit, :play]
  attr :playback, :atom, default: :idle, values: [:idle, :loading, :playing, :paused, :rewound]
  attr :loop?, :boolean, default: false
  attr :instrument_name, :string, default: "the instrument", doc: "named while it loads"
  attr :playback_instrument, :integer, default: 0, doc: "GM program playback uses"
  attr :version_instrument, :integer, default: 0, doc: "GM program saved with the version"
  attr :instrument_options, :list, default: [], doc: "grouped select options (LibraryComponents)"
  slot :trailing, doc: "extra controls at the right end (e.g. save)"
  slot :below_mode, doc: "controls under the Edit/Play switch (e.g. the score layout)"

  @spec palette(map()) :: Phoenix.LiveView.Rendered.t()
  def palette(assigns) do
    assigns =
      assign(assigns,
        values: @values,
        qualities: @qualities,
        numerals: Chords.numerals(assigns.mode)
      )

    ~H"""
    <%!-- A two-row grid: the Edit/Play switch top left, help and save top
         right, and the current mode's two rows of controls between them.
         Each row is a palette piece tall (h-10) in both modes, so switching
         modes doesn't move the score. --%>
    <div
      id="palette"
      role="toolbar"
      aria-label="Palette"
      class="sticky top-0 z-20 grid grid-cols-[auto_auto_1fr_auto] grid-rows-[2.5rem_2.5rem] items-stretch gap-y-1 border-b border-base-300 bg-base-100/95 px-1 py-2 backdrop-blur"
    >
      <div class="join contents" role="group" aria-label="Mode">
        <button
          :for={
            {mode, label, icon} <- [
              {:edit, "Edit", "hero-pencil"},
              {:play, "Play", "hero-speaker-wave"}
            ]
          }
          id={"palette-mode-#{mode}"}
          type="button"
          title={"#{label} mode (P)"}
          aria-pressed={to_string(@editor_mode == mode)}
          phx-click="toggle_mode"
          phx-value-mode={mode}
          class={[
            "btn btn-sm join-item row-start-1 h-auto w-full gap-1 transition-colors",
            mode_column(mode),
            if(@editor_mode == mode, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          <.icon name={icon} class="size-4" />
          {label}
        </button>
      </div>

      <div class="contents">
        {render_slot(@below_mode)}
      </div>

      <div
        :if={@editor_mode == :edit}
        id="palette-edit"
        class="contents"
      >
        <div class="col-start-3 row-start-1 ml-3 flex min-w-0 flex-nowrap items-stretch gap-2">
          <div class="join" role="group" aria-label="Durations">
            <.piece
              :for={{value, label, key, note_glyph, rest_glyph} <- @values}
              id={"palette-#{value}"}
              event="arm"
              kind={@row_kind}
              value={value}
              title={"#{label} #{if @row_kind == :rest, do: "rest", else: "note"} (#{key})"}
              pressed={armed?(@armed, [:note, :rest, :chord], value)}
              glyph={if @row_kind == :rest, do: rest_glyph, else: note_glyph}
            />
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
            <%!-- Chord mode: on while a chord is picked, whichever of length
                 and chord came first; it doesn't apply to rests. --%>
            <details id="palette-chords-menu" class="dropdown join-item">
              <summary
                id="palette-chords"
                aria-pressed={to_string(armed?(@armed, [:chord]))}
                aria-disabled={to_string(@row_kind == :rest)}
                title={chords_title(@row_kind)}
                class={[
                  piece_class(armed?(@armed, [:chord])),
                  "w-auto gap-1 px-3 text-sm",
                  @row_kind == :rest && "pointer-events-none opacity-40"
                ]}
              >
                {chords_label(@armed, @numerals)}
                <.icon name="hero-chevron-down-micro" class="size-4 opacity-60" />
              </summary>
              <div class="dropdown-content z-30 mt-1 w-72 rounded-box border border-base-300 bg-base-100 p-3 shadow-lg">
                <button
                  :if={armed?(@armed, [:chord])}
                  id="palette-single-notes"
                  type="button"
                  phx-click="single_notes"
                  class="mb-3 w-full rounded border border-base-300 px-2 py-1 text-sm transition-colors hover:bg-base-200"
                >
                  Single notes
                </button>
                <p class="mb-1 text-xs opacity-60">Built on the note you click</p>
                <div class="grid grid-cols-4 gap-1">
                  <button
                    :for={quality <- @qualities}
                    id={"palette-chord-#{quality}"}
                    type="button"
                    phx-click="arm_chord"
                    phx-value-quality={quality}
                    class={chip_class(@armed && @armed.chord == {:quality, quality})}
                  >
                    {Chords.name(quality)}
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
        </div>

        <div class="col-start-3 row-start-2 ml-3 flex min-w-0 flex-nowrap items-stretch gap-2">
          <div class="join" role="group" aria-label="Modifiers">
            <.piece
              id="palette-rest-toggle"
              event="toggle_rest"
              title="Rests instead of notes (R)"
              pressed={@row_kind == :rest}
              glyph={:restQuarter}
            />
            <.piece
              id="palette-dot"
              event="toggle_dot"
              title="Dotted (.)"
              pressed={@armed != nil and Map.get(@armed, :dots, 0) > 0}
              glyph={:augmentationDot}
            />
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
              glyph={glyph}
            />
          </div>

          <%!-- One button naming the current placing mode; a click switches it. --%>
          <button
            id="palette-insert"
            type="button"
            title={insert_title(@insert?)}
            aria-pressed={to_string(@insert?)}
            phx-click="toggle_insert"
            class={[
              "btn btn-sm h-auto w-20 transition-colors",
              if(@insert?, do: "btn-primary", else: "btn-outline")
            ]}
          >
            {if @insert?, do: "Insert", else: "Overlay"}
          </button>

          <div class="flex items-stretch gap-1">
            <button
              id="settings-button"
              type="button"
              title="Key, time signature, tempo and pickup"
              phx-click="open_settings"
              class="btn btn-ghost btn-sm btn-square h-auto"
            >
              <.icon name="hero-adjustments-horizontal" class="size-4" />
            </button>
            <button
              id="palette-select-all"
              type="button"
              title="Select all (Ctrl+A)"
              phx-click="select_all"
              class="btn btn-ghost btn-sm btn-square h-auto"
            >
              <.icon name="hero-squares-2x2" class="size-4" />
            </button>
            <button
              id="palette-undo"
              type="button"
              title="Undo (Ctrl+Z)"
              phx-click="undo"
              disabled={!@can_undo?}
              class="btn btn-ghost btn-sm btn-square h-auto"
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" />
            </button>
            <button
              id="palette-redo"
              type="button"
              title="Redo (Ctrl+Shift+Z)"
              phx-click="redo"
              disabled={!@can_redo?}
              class="btn btn-ghost btn-sm btn-square h-auto"
            >
              <.icon name="hero-arrow-uturn-right" class="size-4" />
            </button>
          </div>
        </div>
      </div>

      <div
        :if={@editor_mode == :play}
        id="palette-play-controls"
        class="contents"
      >
        <div
          class="join col-start-3 row-start-1 ml-3 self-center justify-self-start"
          role="group"
          aria-label="Playback"
        >
          <button
            id="palette-rewind"
            type="button"
            title="Back to the start point (Home)"
            phx-click="rewind"
            class="btn btn-ghost btn-sm btn-square join-item"
          >
            <.icon name="hero-backward-solid" class="size-4" />
          </button>
          <button
            id="palette-stop"
            type="button"
            title="Stop, back to the start point (Esc)"
            phx-click="stop"
            class="btn btn-ghost btn-sm btn-square join-item"
          >
            <.icon name="hero-stop-solid" class="size-4" />
          </button>
          <button
            id="palette-play"
            type="button"
            title={play_title(@playback)}
            aria-pressed={to_string(@playback == :playing)}
            phx-click="play"
            class={[
              "btn btn-sm join-item gap-1 transition-colors",
              if(@playback == :playing, do: "btn-warning", else: "btn-ghost")
            ]}
          >
            <.icon name={play_icon(@playback)} class="size-4" />
            {play_label(@playback, @instrument_name)}
          </button>
          <button
            id="palette-skip-measure"
            type="button"
            title="Skip to the next measure"
            aria-label="Skip to the next measure"
            phx-click="skip"
            phx-value-by="measure"
            class="btn btn-ghost btn-sm btn-square join-item"
          >
            <.arrows count={2} />
          </button>
          <button
            id="palette-skip-line"
            type="button"
            title="Skip to the next line of music"
            aria-label="Skip to the next line of music"
            phx-click="skip"
            phx-value-by="line"
            class="btn btn-ghost btn-sm btn-square join-item"
          >
            <.arrows count={3} />
          </button>
          <button
            id="palette-loop"
            type="button"
            title="Repeat the selection, or the whole piece (L)"
            aria-pressed={to_string(@loop?)}
            phx-click="toggle_loop"
            class={[
              "btn btn-sm btn-square join-item transition-colors",
              if(@loop?, do: "btn-primary", else: "btn-ghost")
            ]}
          >
            <.icon name="hero-arrow-path" class="size-4" />
          </button>
        </div>

        <%!-- The picker and its button stay together on one line, the same height. --%>
        <div class="col-start-3 row-start-2 ml-3 flex min-w-0 flex-nowrap items-center gap-2">
          <form
            id="playback-instrument-form"
            phx-change="set_playback_instrument"
            class="w-60 [&_.fieldset]:m-0 [&_.fieldset]:p-0"
          >
            <.input
              id="playback-instrument"
              type="select"
              name="instrument"
              value={@playback_instrument}
              options={@instrument_options}
              aria-label="Playback instrument"
              class="select select-sm w-full"
            />
          </form>
          <button
            id="use-playback-instrument"
            type="button"
            title="Save this instrument with the version"
            phx-click="use_playback_instrument"
            data-confirm={"Use #{@instrument_name} for this version? It's saved with the version when you save."}
            disabled={@playback_instrument == @version_instrument}
            class="btn btn-outline btn-sm h-8 min-h-8 px-3 py-0 text-xs leading-tight whitespace-nowrap transition-colors"
          >
            <span class="flex flex-col items-start">
              <span>Set selection to</span>
              <span>version Instrument</span>
            </span>
          </button>
        </div>
      </div>

      <div class="col-start-4 row-start-1 ml-3 flex items-stretch gap-1">
        <button
          id="palette-help"
          type="button"
          title="Keys and mouse (?)"
          phx-click="open_help"
          class="btn btn-ghost btn-sm btn-square h-auto"
        >
          <.icon name="hero-question-mark-circle" class="size-4" />
        </button>
        {render_slot(@trailing)}
      </div>
    </div>
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
    <div class="flex items-stretch gap-1">
      <span
        :if={@dirty?}
        id="dirty-marker"
        title="Unsaved changes"
        class="size-2 self-center rounded-full bg-warning"
        aria-label="Unsaved changes"
      />
      <div class="join">
        <button
          id="save"
          type="button"
          phx-click="save"
          class="join-item btn btn-primary btn-sm h-auto"
        >
          Save
        </button>
        <details id="save-menu" class="dropdown dropdown-end join-item flex">
          <summary class="btn btn-primary btn-sm btn-square h-auto" aria-label="More ways to save">
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
  attr :kind, :atom, default: nil
  attr :value, :atom, default: nil
  attr :alter, :integer, default: nil
  attr :glyph, :atom, required: true, doc: "the SMuFL glyph it shows"

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
      phx-click={@event}
      phx-value-kind={@kind}
      value={@value}
      phx-value-alter={@alter}
      class={piece_class(@pressed)}
    >
      <svg viewBox={glyph_view_box(@glyph)} style={glyph_size(@glyph)} aria-hidden="true">
        <text font-family="Bravura" font-size="4" fill="currentColor">{Smufl.char(@glyph)}</text>
      </svg>
    </button>
    """
  end

  # A fast-forward icon of `count` arrowheads, like a tape deck's.
  attr :count, :integer, required: true

  defp arrows(assigns) do
    ~H"""
    <svg
      viewBox={"0 0 #{6 * @count + 2} 12"}
      class="h-3.5 w-auto"
      fill="currentColor"
      aria-hidden="true"
    >
      <path :for={i <- 0..(@count - 1)} d={"M#{1 + 6 * i} 1 L#{7 + 6 * i} 6 L#{1 + 6 * i} 11Z"} />
    </svg>
    """
  end

  defp play_label(:playing, _instrument), do: "Pause"
  defp play_label(:paused, _instrument), do: "Resume"
  defp play_label(:rewound, _instrument), do: "Play"
  defp play_label(:loading, instrument), do: "Loading #{instrument}…"
  defp play_label(:idle, _instrument), do: "Play"

  # A piece's glyph is drawn in an SVG in staff spaces (Bravura's em is four
  # of them, y pointing down), boxed by its SMuFL bounding box. The notes
  # share one vertical range, the tallest note's, so their noteheads sit on
  # one line and the 64th's flags stay inside the button.
  defp glyph_view_box(glyph) do
    {x, y, width, height} = glyph_box(glyph)
    Enum.map_join([x, y, width, height], " ", &Float.round(&1 / 1, 3))
  end

  defp glyph_size(glyph) do
    {_x, _y, width, height} = glyph_box(glyph)

    "width: #{Float.round(width * @glyph_rem, 3)}rem; height: #{Float.round(height * @glyph_rem, 3)}rem"
  end

  defp glyph_box(glyph) do
    {x0, y0, x1, y1} = Smufl.bbox(glyph)
    {bottom, top} = vertical_range(glyph, y0, y1)

    {x0 - @glyph_pad, -(top + @glyph_pad), x1 - x0 + 2 * @glyph_pad,
     top - bottom + 2 * @glyph_pad}
  end

  defp vertical_range(glyph, _y0, _y1) when glyph in @note_glyphs, do: @note_range
  defp vertical_range(_glyph, y0, y1), do: {y0, y1}

  # Edit and Play fill the grid's first two columns; Page and Strip
  # (the `:below_mode` slot) fall into the same columns below them.
  defp mode_column(:edit), do: "col-start-1"
  defp mode_column(:play), do: "col-start-2"

  # The Chords button names the chord that's on, so chord mode shows.
  defp chords_label(%{kind: :chord, chord: {:quality, quality}}, _numerals),
    do: "Chord: #{Chords.name(quality)}"

  defp chords_label(%{kind: :chord, chord: {:degree, degree}}, numerals),
    do: "Chord: #{Enum.at(numerals, degree - 1)}"

  defp chords_label(_armed, _numerals), do: "Chords"

  defp chords_title(:rest), do: "Chords don't apply to rests"

  defp chords_title(_row_kind) do
    "Chord mode: place chords at the picked length; with notes selected and nothing picked, turn them into the chord"
  end

  defp insert_title(true = _insert?) do
    "Insert: placing pushes later music on that staff right; deleting pulls it left. Click for Overlay (Ins)"
  end

  defp insert_title(_insert?) do
    "Overlay: a note goes after one still sounding, or joins one starting there; deleting leaves a gap. Click for Insert (Ins)"
  end

  defp play_icon(:playing), do: "hero-pause-solid"
  defp play_icon(_state), do: "hero-play-solid"

  defp play_title(:playing), do: "Pause (Space)"
  defp play_title(:paused), do: "Resume (Space)"
  defp play_title(:rewound), do: "Play from the start point (Space)"

  defp play_title(_state) do
    "Play the selection, from the selected note, or from the start (Space)"
  end

  # A piece of type: score ink on score paper; picked up (inverted, lifted)
  # when armed.
  defp piece_class(pressed) do
    [
      "join-item relative grid h-10 w-10 cursor-pointer place-items-center border border-base-300",
      "transition-all duration-150 focus-visible:outline-2 focus-visible:outline-primary",
      piece_state_class(pressed)
    ]
  end

  defp piece_state_class(true = _pressed) do
    "z-10 -translate-y-0.5 bg-[var(--score-ink)] text-[var(--score-paper)] shadow-md"
  end

  defp piece_state_class(_pressed) do
    "bg-[var(--score-paper)] text-[var(--score-ink)] hover:-translate-y-px"
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
