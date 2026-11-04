defmodule DrawMusicWeb.ScoreComponents do
  @moduledoc """
  Draws an engraved score (see `DrawMusic.Engraving.Layout`) as SVG, from
  the iodata `DrawMusicWeb.ScoreSvg` writes.

  Everything is painted in the current color: on screen the score's `color`
  is the `--score-ink` CSS variable, which follows the light/dark theme;
  the SVG export sets it to black.
  """

  use Phoenix.Component

  # A score draws tens of thousands of items; dev's per-component comments
  # and location attributes would multiply its size several times over,
  # enough for a long piece to time out joining the LiveView.
  @debug_heex_annotations false
  @debug_attributes false

  alias DrawMusicWeb.{ScorePiece, ScoreSvg}

  # Page layout width in staff spaces: about A4's printable width at a
  # 1.75 mm staff space.
  @page_width 104

  @doc "Space left of the first system in the score's viewBox, in staff spaces."
  @spec padding() :: number()
  def padding, do: ScoreSvg.padding()

  @doc "System width for page layout, in staff spaces."
  @spec page_width() :: number()
  def page_width, do: @page_width

  @doc "Layout options for a user's preferred score layout (`:strip` or `:page`)."
  @spec layout_width(:strip | :page) :: :infinity | number()
  def layout_width(:page), do: @page_width
  def layout_width(:strip), do: :infinity

  @doc """
  The score as the editor draws it: its pieces (`ScoreSvg.pieces/3`), each
  its own `<svg>`, stacked down the page (Page) or along it (Strip). The
  browser skips drawing the pieces out of view, and LiveView resends only
  the pieces that change. `data-view-box` is the whole score's viewBox.
  """
  attr :id, :string, required: true
  attr :layout, :map, required: true, doc: "the engraved score"
  attr :pieces, :list, required: true
  attr :space, :integer, default: 10, doc: "pixels per staff space (Strip)"
  attr :strip?, :boolean, default: false

  @spec score(map()) :: Phoenix.LiveView.Rendered.t()
  def score(assigns) do
    padding = ScoreSvg.padding()

    assigns =
      assign(assigns,
        view_box: "#{-padding} 0 #{assigns.layout.width + 2 * padding} #{assigns.layout.height}"
      )

    ~H"""
    <div
      id={@id}
      class={if(@strip?, do: "flex w-fit", else: "flex flex-col")}
      style="color: var(--score-ink)"
      data-view-box={@view_box}
      role="img"
      aria-label="Score"
    >
      <div
        :for={piece <- @pieces}
        id={piece.id}
        class="score-piece"
        style={piece_style(piece, @space)}
      >
        {Phoenix.HTML.raw(ScoreSvg.piece(piece, @space))}
      </div>
    </div>
    """
  end

  @doc """
  The systems of a layout, in staff-space units, painted in `currentColor`
  (for the SVG export). Selected notes and rests get the `selected` class.
  """
  attr :layout, :map, required: true
  attr :selection, :any, default: MapSet.new()

  @spec systems(map()) :: Phoenix.LiveView.Rendered.t()
  def systems(assigns) do
    ~H"""
    {Phoenix.HTML.raw(ScoreSvg.systems(@layout.systems, @selection))}
    """
  end

  # A piece keeps its size while the browser skips drawing it: Page pieces
  # by their shape at the column's width, Strip pieces in pixels.
  defp piece_style(%ScorePiece{whole?: true} = piece, _space) do
    "aspect-ratio: #{piece.x1 - piece.x0} / #{piece.y1 - piece.y0}"
  end

  defp piece_style(%ScorePiece{} = piece, space) do
    "width: #{(piece.x1 - piece.x0) * space}px; height: #{(piece.y1 - piece.y0) * space}px"
  end
end
