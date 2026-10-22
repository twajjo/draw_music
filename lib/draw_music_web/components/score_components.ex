defmodule DrawMusicWeb.ScoreComponents do
  @moduledoc """
  Draws an engraved score (see `DrawMusic.Engraving.Layout`) as SVG.

  Glyphs are Bravura text, one em being four staff spaces. Everything is
  painted in the current color: on screen the score's `color` is the
  `--score-ink` CSS variable, which follows the light/dark theme; the SVG
  export sets it to black.
  """

  use Phoenix.Component

  alias DrawMusic.Engraving.{Beam, Brace, Glyph, Line, Smufl, Tie}

  # SMuFL fonts are scaled so that one em is four staff spaces.
  @font_size 4
  @padding 1
  # Page layout width in staff spaces: about A4's printable width at a
  # 1.75 mm staff space.
  @page_width 104

  @doc "Space left of the first system in the score's viewBox, in staff spaces."
  @spec padding() :: number()
  def padding, do: @padding

  @doc "System width for page layout, in staff spaces."
  @spec page_width() :: number()
  def page_width, do: @page_width

  @doc "Layout options for a user's preferred score layout (`:strip` or `:page`)."
  @spec layout_width(:strip | :page) :: :infinity | number()
  def layout_width(:page), do: @page_width
  def layout_width(:strip), do: :infinity

  @doc "The score as an SVG element sized at `space` pixels per staff space."
  attr :id, :string, required: true
  attr :layout, :map, required: true
  attr :space, :integer, default: 10, doc: "pixels per staff space"
  attr :class, :any, default: nil
  attr :selection, :any, default: MapSet.new(), doc: "ids of selected notes and rests"

  @spec score(map()) :: Phoenix.LiveView.Rendered.t()
  def score(assigns) do
    assigns = assign(assigns, :padding, @padding)

    ~H"""
    <svg
      id={@id}
      xmlns="http://www.w3.org/2000/svg"
      viewBox={"#{-@padding} 0 #{n(@layout.width + 2 * @padding)} #{n(@layout.height)}"}
      width={n((@layout.width + 2 * @padding) * @space)}
      height={n(@layout.height * @space)}
      style="color: var(--score-ink)"
      class={@class}
      role="img"
      aria-label="Score"
    >
      <.systems layout={@layout} selection={@selection} />
    </svg>
    """
  end

  @doc """
  The systems of a layout, in staff-space units, painted in `currentColor`.
  Selected notes and rests get the `selected` class.
  """
  attr :layout, :map, required: true
  attr :selection, :any, default: MapSet.new()

  @spec systems(map()) :: Phoenix.LiveView.Rendered.t()
  def systems(assigns) do
    assigns = assign(assigns, :font_size, @font_size)

    ~H"""
    <g
      :for={system <- @layout.systems}
      id={"system-#{system.index}"}
      transform={"translate(0 #{n(system.y)})"}
      font-family="Bravura"
      font-size={@font_size}
      fill="currentColor"
    >
      <.item :for={item <- system.items} item={item} selection={@selection} />
    </g>
    """
  end

  attr :item, :map, required: true
  attr :selection, :any, default: MapSet.new()

  defp item(%{item: %Glyph{}} = assigns) do
    ~H"""
    <text
      id={dom_id(@item)}
      class={MapSet.member?(@selection, @item.id) && "selected"}
      x={n(@item.x)}
      y={n(@item.y)}
    >
      {Smufl.char(@item.glyph)}
    </text>
    """
  end

  defp item(%{item: %Line{}} = assigns) do
    ~H"""
    <line
      x1={n(@item.x1)}
      y1={n(@item.y1)}
      x2={n(@item.x2)}
      y2={n(@item.y2)}
      stroke="currentColor"
      stroke-width={n(@item.thickness)}
    />
    """
  end

  defp item(%{item: %Beam{}} = assigns) do
    ~H"""
    <polygon points={beam_points(@item)} />
    """
  end

  defp item(%{item: %Tie{}} = assigns) do
    ~H"""
    <path d={tie_path(@item)} />
    """
  end

  # The brace glyph is one staff tall at the normal size; scale the font so
  # it spans the grand staff.
  defp item(%{item: %Brace{}} = assigns) do
    ~H"""
    <text x={n(@item.x)} y={n(@item.y2)} font-size={n(@item.y2 - @item.y1)}>
      {Smufl.char(:brace)}
    </text>
    """
  end

  defp dom_id(%Glyph{role: :notehead, id: id}), do: "note-#{id}"
  defp dom_id(%Glyph{role: :rest, id: id}) when is_binary(id), do: "rest-#{id}"
  defp dom_id(_item), do: nil

  defp beam_points(%Beam{x1: x1, y1: y1, x2: x2, y2: y2, thickness: t}) do
    Enum.map_join([{x1, y1}, {x2, y2}, {x2, y2 + t}, {x1, y1 + t}], " ", fn {x, y} ->
      "#{n(x)},#{n(y)}"
    end)
  end

  # Two quadratic curves between the endpoints: the outer one bulges `dir`,
  # the inner one a little less, leaving the tie its midpoint thickness.
  defp tie_path(%Tie{x1: x1, x2: x2, y: y, dir: dir}) do
    sign = if dir == :down, do: 1, else: -1
    height = (x2 - x1) |> Kernel.*(0.2) |> max(0.6) |> min(1.8)
    inner = height - 2 * Smufl.default("tieMidpointThickness")
    mid = (x1 + x2) / 2

    "M#{n(x1)} #{n(y)} Q#{n(mid)} #{n(y + sign * height)} #{n(x2)} #{n(y)} " <>
      "Q#{n(mid)} #{n(y + sign * inner)} #{n(x1)} #{n(y)}Z"
  end

  defp n(x) when is_integer(x), do: x
  defp n(x) when is_float(x), do: Float.round(x, 3)
end
