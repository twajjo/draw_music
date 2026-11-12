defmodule DrawMusicWeb.Palette.Buttons do
  @moduledoc """
  The two button shells the palette is built from, so their classes live
  in one place:

    * `tool_button/1`: a daisyUI button for a tool, a toggle or a transport
      control;
    * `piece/1`: a piece of type showing a Bravura glyph in score ink on
      score paper, drawn "picked up" (inverted and lifted) while armed.
      `piece_class/1` gives other piece-shaped controls (tie, chords) the
      same look.
  """

  use Phoenix.Component

  alias DrawMusic.Engraving.Smufl

  @note_glyphs ~w(noteWhole noteHalfUp noteQuarterUp note8thUp note16thUp note32ndUp
                  note64thUp note128thUp note256thUp)a
  # SMuFL y (up) from the lowest notehead's bottom to the 256th's flag tip.
  @note_range {-0.6, 6.4}
  # Staff spaces around each glyph, rem per staff space, and the tallest a
  # glyph may be drawn (rem).
  @glyph_pad 0.2
  @glyph_rem 0.34
  @glyph_max_rem 2.0

  @doc "A palette piece: a button showing one glyph."
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :title, :string, required: true
  attr :pressed, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :kind, :atom, default: nil
  attr :value, :atom, default: nil
  attr :alter, :integer, default: nil
  attr :target, :any, default: nil, doc: "the component its click goes to"
  attr :glyph, :atom, required: true, doc: "the SMuFL glyph it shows"

  attr :own_box, :boolean,
    default: false,
    doc: "box a note glyph by itself, centred, not on the duration row's shared range"

  @spec piece(map()) :: Phoenix.LiveView.Rendered.t()
  def piece(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      title={@title}
      aria-label={@title}
      aria-pressed={to_string(@pressed)}
      disabled={@disabled}
      data-kind={@kind}
      data-value={@value}
      phx-click={@event}
      phx-target={@target}
      phx-value-kind={@kind}
      value={@value}
      phx-value-alter={@alter}
      class={piece_class(@pressed)}
    >
      <svg
        viewBox={glyph_view_box(@glyph, @own_box)}
        style={glyph_size(@glyph, @own_box)}
        aria-hidden="true"
      >
        <text font-family="Bravura" font-size="4" fill="currentColor">{Smufl.char(@glyph)}</text>
      </svg>
    </button>
    """
  end

  @doc """
  A piece of type's classes: score ink on score paper; picked up (inverted,
  lifted) when `pressed`.
  """
  @spec piece_class(boolean()) :: list()
  def piece_class(pressed) do
    [
      "join-item relative grid h-10 w-10 cursor-pointer place-items-center border border-base-300",
      "transition-all duration-150 focus-visible:outline-2 focus-visible:outline-primary",
      "disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:translate-y-0",
      piece_state_class(pressed)
    ]
  end

  @doc """
  A tool's button. A toggle passes `pressed` (shown as `on`, else `off`);
  other buttons leave it out and look `off`. `class` adds placement and
  size; `rest` carries `phx-value-*`, `aria-label` and `data-confirm`.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :click, :any, required: true, doc: "the event name, or a JS command"
  attr :target, :any, default: nil, doc: "the component its click goes to"
  attr :disabled, :boolean, default: false
  attr :pressed, :boolean, default: nil, doc: "nil for a button that isn't a toggle"
  attr :on, :string, default: "btn-primary", doc: "the look while pressed"
  attr :off, :string, default: "btn-ghost", doc: "the look otherwise"
  attr :square, :boolean, default: true, doc: "an icon's square, not a labelled button"
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(phx-value-mode phx-value-by phx-value-dir aria-label data-confirm)

  slot :inner_block, required: true

  @spec tool_button(map()) :: Phoenix.LiveView.Rendered.t()
  def tool_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      title={@title}
      aria-pressed={@pressed != nil && to_string(@pressed)}
      disabled={@disabled}
      phx-click={@click}
      phx-target={@target}
      class={[
        "btn btn-sm transition-colors",
        @square && "btn-square",
        if(@pressed, do: @on, else: @off),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp glyph_box(glyph, own_box?) do
    {x0, y0, x1, y1} = Smufl.bbox(glyph)
    {bottom, top} = vertical_range(glyph, own_box?, y0, y1)

    {x0 - @glyph_pad, -(top + @glyph_pad), x1 - x0 + 2 * @glyph_pad,
     top - bottom + 2 * @glyph_pad}
  end

  # Glyphs taller than @glyph_max_rem (the 128th and 256th, whose flags
  # reach highest) are drawn smaller to fit the button.
  defp glyph_size(glyph, own_box?) do
    {_x, _y, width, height} = glyph_box(glyph, own_box?)
    scale = min(@glyph_rem, @glyph_max_rem / height)

    "width: #{Float.round(width * scale, 3)}rem; height: #{Float.round(height * scale, 3)}rem"
  end

  # A piece's glyph is drawn in an SVG in staff spaces (Bravura's em is four
  # of them, y pointing down), boxed by its SMuFL bounding box. The notes
  # share one vertical range, the tallest note's, so their noteheads sit on
  # one line and the 64th's flags stay inside the button.
  defp glyph_view_box(glyph, own_box?) do
    {x, y, width, height} = glyph_box(glyph, own_box?)
    Enum.map_join([x, y, width, height], " ", &Float.round(&1 / 1, 3))
  end

  defp piece_state_class(true = _pressed) do
    "z-10 -translate-y-0.5 bg-[var(--score-ink)] text-[var(--score-paper)] shadow-md"
  end

  defp piece_state_class(_pressed) do
    "bg-[var(--score-paper)] text-[var(--score-ink)] hover:-translate-y-px"
  end

  defp vertical_range(glyph, false, _y0, _y1) when glyph in @note_glyphs, do: @note_range

  # The half rest sits on the button's middle and the whole rest hangs from
  # it, as they do from their staff lines, so the two look different.
  defp vertical_range(:restHalf, _own_box?, y0, y1), do: {y0 - (y1 - y0), y1}
  defp vertical_range(:restWhole, _own_box?, y0, y1), do: {y0, y1 + (y1 - y0)}
  defp vertical_range(_glyph, _own_box?, y0, y1), do: {y0, y1}
end
