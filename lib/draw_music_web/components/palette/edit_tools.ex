defmodule DrawMusicWeb.Palette.EditTools do
  @moduledoc """
  The palette's two rows in Edit mode. The first holds what is placed: the
  durations, the meter's beat (a sign, not a button: B arms it), then tie
  and the chords menu. The second holds how it is
  placed: the modifiers (rest, dot, accidentals), the Insert/Overlay
  switch, Suggest key (`DrawMusicWeb.Palette.KeyMenu`), then settings,
  select all, undo and redo.

  A click arms a piece, and it stays armed until another is picked; the
  armed state lives on the server (see `DrawMusicWeb.EditorPalette`).
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1]
  import DrawMusicWeb.Palette.Buttons
  import DrawMusicWeb.Palette.KeyMenu

  alias DrawMusic.Engraving.Smufl
  alias DrawMusic.Music.{Chords, KeySuggestion}
  alias DrawMusicWeb.{Dropdown, EditorPalette}
  alias Phoenix.LiveView.JS

  @values [
    {:whole, "Whole", "1", :noteWhole, :restWhole},
    {:half, "Half", "2", :noteHalfUp, :restHalf},
    {:quarter, "Quarter", "3", :noteQuarterUp, :restQuarter},
    {:eighth, "Eighth", "4", :note8thUp, :rest8th},
    {:sixteenth, "16th", "5", :note16thUp, :rest16th},
    {:thirty_second, "32nd", "6", :note32ndUp, :rest32nd},
    {:sixty_fourth, "64th", "7", :note64thUp, :rest64th},
    {:hundred_twenty_eighth, "128th", "8", :note128thUp, :rest128th},
    {:two_hundred_fifty_sixth, "256th", "9", :note256thUp, :rest256th}
  ]

  # Where the beat sign's dots go (`beat_sign/1`), in staff spaces: past
  # the stem, at the notehead's height.
  @beat_dot_x 1.7
  @beat_dot_gap 0.6

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

  @accidentals [
    {"sharp", 1, :accidentalSharp, "Sharp (hold Shift)"},
    {"flat", -1, :accidentalFlat, "Flat (hold Ctrl or Alt)"},
    {"natural", 0, :accidentalNatural, "Natural"}
  ]

  @doc "Edit mode's two rows: what is placed, then how."
  attr :armed, :map, default: nil
  attr :row_kind, :atom, default: :note, values: [:note, :rest]
  attr :insert?, :boolean, default: false

  attr :beat, :any,
    default: {:quarter, 0},
    doc: "the value that is one beat in the meter, as `{value, dots}`, shown beside the durations"

  attr :can_undo?, :boolean, default: false
  attr :can_redo?, :boolean, default: false
  attr :mode, :atom, default: :major, doc: "the key's mode, for chord numerals"

  attr :key_suggestion, KeySuggestion,
    required: true,
    doc: "better keys for the score, for the Suggest key button"

  attr :target, :any, default: nil, doc: "the component the controls' clicks go to"
  @spec edit_tools(map()) :: Phoenix.LiveView.Rendered.t()
  def edit_tools(assigns) do
    ~H"""
    <div id="palette-edit" class="contents">
      <div class="col-start-3 row-start-1 ml-3 flex min-w-0 flex-nowrap items-stretch gap-2">
        <.durations armed={@armed} row_kind={@row_kind} target={@target} />
        <.beat_sign beat={@beat} />
        <div class="join" role="group" aria-label="Ties and chords">
          <.tie_button armed={@armed} target={@target} />
          <.chords_menu
            armed={@armed}
            row_kind={@row_kind}
            numerals={Chords.numerals(@mode)}
            target={@target}
          />
        </div>
      </div>

      <div class="col-start-3 row-start-2 ml-3 flex min-w-0 flex-nowrap items-stretch gap-2">
        <.modifiers armed={@armed} row_kind={@row_kind} target={@target} />
        <.placing_toggle insert?={@insert?} target={@target} />
        <.key_menu suggestion={@key_suggestion} target={@target} />
        <.history_tools can_undo?={@can_undo?} can_redo?={@can_redo?} target={@target} />
      </div>
    </div>
    """
  end

  defp armed?(nil, _kinds), do: false
  defp armed?(%{kind: kind}, kinds), do: kind in kinds

  defp armed?(nil, _kinds, _value), do: false
  defp armed?(%{kind: kind, value: value}, kinds, wanted), do: kind in kinds and value == wanted

  attr :beat, :any, required: true
  # "Beat:" over the value that is one beat in the meter, drawn as in a score:
  # a quarter in 4/4, a dotted quarter in 6/8. Not a button: B arms it.
  defp beat_sign(assigns) do
    {value, dots} = assigns.beat

    assigns =
      assign(assigns,
        value: value,
        glyph: note_glyph(value),
        dots: dots,
        dot_x: @beat_dot_x,
        dot_gap: @beat_dot_gap
      )

    ~H"""
    <div
      id="palette-beat"
      data-value={@value}
      data-dots={@dots}
      title={beat_title(@dots)}
      class="flex shrink-0 flex-col items-center justify-center text-base-content/70"
    >
      <span class="text-[0.65rem] leading-none">Beat:</span>
      <svg viewBox={beat_view_box(@glyph, @dots)} class="mt-0.5 h-5 w-auto" aria-hidden="true">
        <text font-family="Bravura" font-size="4" fill="currentColor">{Smufl.char(@glyph)}</text>
        <text
          :for={dot <- 1..@dots//1}
          x={@dot_x + (dot - 1) * @dot_gap}
          font-family="Bravura"
          font-size="4"
          fill="currentColor"
          class="beat-dot"
        >
          {Smufl.char(:augmentationDot)}
        </text>
      </svg>
    </div>
    """
  end

  defp beat_title(0), do: "One beat in this meter (B arms it)"
  defp beat_title(_dots), do: "One beat in this meter is dotted (B arms it)"

  # The sign's box, in staff spaces (y down): the note on the duration row's
  # range, and room for its dots past the notehead.
  defp beat_view_box(glyph, dots) do
    {_x0, _y0, x1, _y1} = Smufl.bbox(glyph)
    right = max(x1, @beat_dot_x + dots * @beat_dot_gap)
    Enum.map_join([-0.1, -3.6, right + 0.1, 4.3], " ", &Float.round(&1 / 1, 3))
  end

  defp chip_class(selected) do
    [
      "rounded px-2 py-1 text-sm transition-colors",
      if(selected, do: "bg-primary text-primary-content", else: "hover:bg-base-200")
    ]
  end

  # The Chords button names the chord that's on, so chord mode shows.
  defp chords_label(%{kind: :chord, chord: {:quality, quality}}, _numerals) do
    "Chord: #{Chords.name(quality)}"
  end

  defp chords_label(%{kind: :chord, chord: {:degree, degree}}, numerals) do
    "Chord: #{Enum.at(numerals, degree - 1)}"
  end

  defp chords_label(_armed, _numerals), do: "Chords"

  attr :armed, :map, required: true
  attr :row_kind, :atom, required: true
  attr :numerals, :list, required: true
  attr :target, :any, required: true
  # Chord mode: on while a chord is picked, whichever of length and chord
  # came first; it doesn't apply to rests.
  defp chords_menu(assigns) do
    assigns = assign(assigns, :qualities, @qualities)

    ~H"""
    <Dropdown.dropdown id="palette-chords-menu" class="join-item">
      <:summary
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
      </:summary>
      <div class="dropdown-content z-30 mt-1 w-72 rounded-box border border-base-300 bg-base-100 p-3 shadow-lg">
        <button
          :if={armed?(@armed, [:chord])}
          id="palette-single-notes"
          type="button"
          phx-click={pick("single_notes", @target)}
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
            phx-click={pick("arm_chord", @target)}
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
            phx-click={pick("arm_chord", @target)}
            phx-value-degree={degree}
            class={chip_class(@armed && @armed.chord == {:degree, degree})}
          >
            {numeral}
          </button>
        </div>
      </div>
    </Dropdown.dropdown>
    """
  end

  defp chords_title(:rest), do: "Chords don't apply to rests"

  defp chords_title(_row_kind) do
    "Chord mode: place chords at the picked length; with notes selected and nothing picked, turn them into the chord"
  end

  defp dot_title(armed) do
    case EditorPalette.dottable?(armed) do
      true -> "Dotted (.)"
      false -> "A 256th can't be dotted"
    end
  end

  # A length's tooltip.
  defp duration_title(label, key, row_kind) do
    kind = if row_kind == :rest, do: "rest", else: "note"
    "#{label} #{kind} (#{key})"
  end

  attr :armed, :map, required: true
  attr :row_kind, :atom, required: true
  attr :target, :any, required: true
  # The lengths, as notes or rests (the rest toggle switches the row).
  defp durations(assigns) do
    assigns = assign(assigns, :values, @values)

    ~H"""
    <div class="join" role="group" aria-label="Durations">
      <.piece
        :for={{value, label, key, note_glyph, rest_glyph} <- @values}
        id={"palette-#{value}"}
        event="arm"
        kind={@row_kind}
        value={value}
        title={duration_title(label, key, @row_kind)}
        pressed={armed?(@armed, [:note, :rest, :chord], value)}
        glyph={if @row_kind == :rest, do: rest_glyph, else: note_glyph}
        target={@target}
      />
    </div>
    """
  end

  attr :can_undo?, :boolean, required: true
  attr :can_redo?, :boolean, required: true
  attr :target, :any, required: true
  # Settings, select all, undo and redo.
  defp history_tools(assigns) do
    ~H"""
    <div class="flex items-stretch gap-1">
      <.tool_button
        id="settings-button"
        title="Key, time signature, tempo and pickup"
        click="open_settings"
        target={@target}
        class="h-auto"
      >
        <.icon name="hero-cog-6-tooth" class="size-4" />
      </.tool_button>
      <.tool_button
        id="palette-select-all"
        title="Select all (Ctrl+A)"
        click="select_all"
        target={@target}
        class="h-auto"
      >
        <.icon name="hero-squares-2x2" class="size-4" />
      </.tool_button>
      <.tool_button
        id="palette-undo"
        title="Undo (Ctrl+Z)"
        click="undo"
        target={@target}
        disabled={!@can_undo?}
        class="h-auto"
      >
        <.icon name="hero-arrow-uturn-left" class="size-4" />
      </.tool_button>
      <.tool_button
        id="palette-redo"
        title="Redo (Ctrl+Shift+Z)"
        click="redo"
        target={@target}
        disabled={!@can_redo?}
        class="h-auto"
      >
        <.icon name="hero-arrow-uturn-right" class="size-4" />
      </.tool_button>
    </div>
    """
  end

  # A value's note glyph, as on its button.
  defp note_glyph(value) do
    {^value, _label, _key, glyph, _rest} = List.keyfind(@values, value, 0)
    glyph
  end

  defp insert_title(true = _insert?) do
    "Insert: placing pushes later music on that staff right; deleting pulls it left. Click for Overlay (Ins)"
  end

  defp insert_title(_insert?) do
    "Overlay: a note goes after one still sounding, or joins one starting there; deleting leaves a gap. Click for Insert (Ins)"
  end

  attr :armed, :map, required: true
  attr :row_kind, :atom, required: true
  attr :target, :any, required: true
  # Rest or note, the dot and the accidentals.
  defp modifiers(assigns) do
    assigns = assign(assigns, :accidentals, @accidentals)

    ~H"""
    <div class="join" role="group" aria-label="Modifiers">
      <.piece
        id="palette-rest-toggle"
        event="toggle_rest"
        title={row_kind_title(@row_kind)}
        pressed={@row_kind == :rest}
        glyph={if @row_kind == :rest, do: :noteQuarterUp, else: :restQuarter}
        own_box
        target={@target}
      />
      <.piece
        id="palette-dot"
        event="toggle_dot"
        title={dot_title(@armed)}
        pressed={@armed != nil and Map.get(@armed, :dots, 0) > 0}
        disabled={!EditorPalette.dottable?(@armed)}
        glyph={:augmentationDot}
        target={@target}
      />
      <.piece
        :for={{id, alter, glyph, label} <- @accidentals}
        id={"palette-#{id}"}
        event="set_accidental"
        alter={alter}
        title={label}
        pressed={@armed != nil and Map.get(@armed, :alter) == alter}
        glyph={glyph}
        target={@target}
      />
    </div>
    """
  end

  attr :insert?, :boolean, required: true
  attr :target, :any, required: true
  # One button naming the current placing mode; a click switches it.
  defp placing_toggle(assigns) do
    ~H"""
    <.tool_button
      id="palette-insert"
      title={insert_title(@insert?)}
      click="toggle_insert"
      target={@target}
      pressed={@insert?}
      off="btn-outline"
      square={false}
      class="h-auto w-20"
    >
      {if @insert?, do: "Insert", else: "Overlay"}
    </.tool_button>
    """
  end

  # A Chords menu item: the menu closes, then `event` goes to the palette
  # (with the item's phx-value-* attributes).
  defp pick(event, target) do
    "palette-chords-menu"
    |> Dropdown.close()
    |> JS.push(event, target: target)
  end

  # The button shows what it switches to.
  defp row_kind_title(:rest), do: "Switch to note (R)"
  defp row_kind_title(_note), do: "Switch to rest (R)"

  attr :armed, :map, required: true
  attr :target, :any, required: true

  defp tie_button(assigns) do
    ~H"""
    <button
      id="palette-tie"
      type="button"
      title="Tie: drag from one note to the next (T)"
      aria-pressed={to_string(armed?(@armed, [:tie]))}
      phx-click="arm_tie"
      phx-target={@target}
      class={piece_class(armed?(@armed, [:tie]))}
    >
      <svg viewBox="0 0 24 12" class="h-3 w-6" aria-hidden="true">
        <path d="M2 3 Q12 12 22 3 Q12 9 2 3Z" fill="currentColor" />
      </svg>
    </button>
    """
  end
end
