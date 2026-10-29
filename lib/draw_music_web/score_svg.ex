defmodule DrawMusicWeb.ScoreSvg do
  @moduledoc """
  Writes an engraved score (see `DrawMusic.Engraving.Layout`) as SVG
  iodata, item by item, and cuts it into the pieces the editor draws
  (`DrawMusicWeb.ScorePiece`).

  A long score has tens of thousands of items, so they're written straight
  to iodata rather than through a HEEx component each. Glyphs are Bravura
  text, one em being four staff spaces, painted in the current color.
  Selected notes, rests and tempo marks get the `selected` class.
  """

  alias DrawMusic.Engraving.{Beam, Brace, Engraved, Glyph, Line, Smufl, System, TempoMark, Tie}
  alias DrawMusicWeb.ScorePiece

  # SMuFL fonts are scaled so that one em is four staff spaces.
  @font_size 4
  # Tempo marks (staff spaces): text size; the metronome note's size and the
  # room it takes; the dashed line's height above the baseline; the gap
  # before the end tempo, and room enough for the end tempo's words.
  @tempo_font_size 1.8
  @tempo_note_size 2.6
  @tempo_note_width 1.3
  @tempo_line_rise 0.5
  @tempo_end_gap 0.4
  @tempo_end_room 8
  # A tie's arch rises with its length, within limits (staff spaces).
  @tie_rise 0.2
  @tie_min_height 0.6
  @tie_max_height 1.8
  # Space left and right of the systems, in staff spaces.
  @padding 1
  # Strip layout is cut into pieces of this many bars.
  @strip_bars 16
  # Decimal places kept in SVG numbers.
  @precision 3

  @doc "Space left and right of the systems in the score's viewBox, in staff spaces."
  @spec padding() :: number()
  def padding, do: @padding

  @doc "Whole systems as SVG groups (`<g>`), in staff-space units."
  @spec systems([System.t()], MapSet.t()) :: iodata()
  def systems(systems, selection) do
    Enum.map(systems, &group({&1.index, &1.y, &1.items}, true, selection, :all))
  end

  @doc """
  The pieces the editor draws a layout in: one per system in Page layout,
  runs of #{@strip_bars} bars of the one system in Strip layout. Nothing is
  selected in them yet (`select/2`).
  """
  @spec pieces(Engraved.t(), :page | :strip) :: [ScorePiece.t()]
  def pieces(%Engraved{systems: systems} = engraved, :page) do
    for system <- systems do
      %ScorePiece{
        id: "system-#{system.index}",
        x0: -@padding,
        x1: engraved.width + @padding,
        y0: system.top,
        y1: system.bottom,
        groups: [{system.index, system.y, system.items}],
        whole?: true
      }
    end
  end

  def pieces(%Engraved{systems: [system]} = engraved, :strip) do
    edges = strip_edges(system, engraved.width)
    runs = edges |> Enum.zip(tl(edges)) |> Enum.with_index()
    starts = edges |> Enum.drop(-1) |> List.to_tuple()

    by_run =
      system.items
      |> Enum.flat_map(fn item ->
        {from, to} = x_span(item)
        for index <- run_at(starts, from)..run_at(starts, to)//1, do: {index, item}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for {{x0, x1}, index} <- runs do
      %ScorePiece{
        id: "strip-#{index}",
        x0: x0,
        x1: x1,
        y0: 0.0,
        y1: engraved.height,
        groups: [{system.index, system.y, Map.get(by_run, index, [])}],
        whole?: false
      }
    end
  end

  # A score with no systems, or Strip laid out as several, draws whole.
  def pieces(%Engraved{} = engraved, _layout), do: pieces(engraved, :page)

  @doc "A piece's `<svg>`, sized at `space` pixels per staff space in Strip layout."
  @spec piece(ScorePiece.t(), pos_integer()) :: iodata()
  def piece(%ScorePiece{} = piece, space) do
    width = piece.x1 - piece.x0
    height = piece.y1 - piece.y0
    range = if piece.whole?, do: :all, else: {piece.x0, piece.x1}

    [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="),
      join([piece.x0, piece.y0, width, height], " "),
      ~s(" ),
      size(piece.whole?, width, height, space),
      ~s(>),
      Enum.map(piece.groups, &group(&1, false, piece.selected, range)),
      "</svg>"
    ]
  end

  # Page pieces fill the column's width; Strip pieces are drawn to scale.
  defp size(true = _whole?, _width, _height, _space), do: ~s(class="block h-auto w-full")

  defp size(false, width, height, space) do
    [~s(class="block" width="), n(width * space), ~s(" height="), n(height * space), ~s(")]
  end

  # Runs of bars, each starting at its first bar's left edge; the first and
  # last reach the score's edges.
  defp strip_edges(%System{measures: measures}, width) do
    starts =
      measures
      |> Enum.chunk_every(@strip_bars)
      |> Enum.drop(1)
      |> Enum.map(&hd(&1).x)

    [-@padding | starts] ++ [width + @padding]
  end

  # The x range an item takes. Glyphs and the brace count only where they
  # start, so each lands in one run and keeps a single element; lines,
  # beams, ties and tempo marks go in every run they cross, each drawing
  # (and clipping) its part.
  defp x_span(%Glyph{x: x}), do: {x, x}
  defp x_span(%Brace{x: x}), do: {x, x}

  defp x_span(%TempoMark{} = mark) do
    {mark.x, (mark.line_to || mark.x + mark.width) + @tempo_end_room}
  end

  defp x_span(%{x1: a, x2: b}), do: {min(a, b), max(a, b)}

  # The run holding x: the last whose start is at or before it (the first
  # for anything left of the score).
  defp run_at(starts, x), do: run_at(starts, x, 0, tuple_size(starts) - 1)

  defp run_at(_starts, _x, low, high) when low >= high, do: low

  defp run_at(starts, x, low, high) do
    mid = div(low + high + 1, 2)

    case elem(starts, mid) <= x do
      true -> run_at(starts, x, mid, high)
      false -> run_at(starts, x, low, mid - 1)
    end
  end

  @doc "Marks which of each piece's notes, rests and tempo marks are in `selection`."
  @spec select([ScorePiece.t()], MapSet.t()) :: [ScorePiece.t()]
  def select(pieces, selection), do: Enum.map(pieces, &select_in(&1, selection))

  defp select_in(%ScorePiece{} = piece, selection) do
    selected =
      for {_index, _y, items} <- piece.groups,
          item <- items,
          id = selectable_id(item),
          MapSet.member?(selection, id),
          into: MapSet.new(),
          do: id

    %{piece | selected: selected}
  end

  defp selectable_id(%Glyph{id: id}), do: id
  defp selectable_id(%TempoMark{id: id}), do: id
  defp selectable_id(_item), do: nil

  # A system's items under its translation, with its index. In the export
  # it also has the system's id (the editor gives that to the piece).
  defp group({index, y, items}, id?, selection, range) do
    [
      "<g",
      attr("id", id? && "system-#{index}"),
      attr("data-system", index),
      attr("transform", ["translate(0 ", n(y), ")"]),
      attr("font-family", "Bravura"),
      attr("font-size", @font_size),
      attr("fill", "currentColor"),
      ">",
      Enum.map(items, &item(&1, selection, range)),
      "</g>"
    ]
  end

  defp item(%Glyph{} = glyph, selection, _range) do
    [
      "<text",
      attr("id", dom_id(glyph)),
      attr("class", MapSet.member?(selection, glyph.id) && "selected"),
      attr("data-staff", glyph.staff),
      attr("x", n(glyph.x)),
      attr("y", n(glyph.y)),
      ">",
      Smufl.char(glyph.glyph),
      "</text>"
    ]
  end

  defp item(%Line{} = line, _selection, _range) do
    [
      "<line",
      attr("x1", n(line.x1)),
      attr("y1", n(line.y1)),
      attr("x2", n(line.x2)),
      attr("y2", n(line.y2)),
      attr("stroke", "currentColor"),
      attr("stroke-width", n(line.thickness)),
      "/>"
    ]
  end

  defp item(%Beam{} = beam, _selection, _range),
    do: ["<polygon", attr("points", beam_points(beam)), "/>"]

  defp item(%Tie{} = tie, _selection, _range), do: ["<path", attr("d", tie_path(tie)), "/>"]

  # The brace glyph is one staff tall at the normal size; scale the font so
  # it spans the grand staff.
  defp item(%Brace{} = brace, _selection, _range) do
    [
      "<text",
      attr("x", n(brace.x)),
      attr("y", n(brace.y2)),
      attr("font-size", n(brace.y2 - brace.y1)),
      ">",
      Smufl.char(:brace),
      "</text>"
    ]
  end

  # A tempo change: its label (selectable, draggable), and for a rit. or
  # accel. the dashed line and the end tempo (its end, draggable). A piece
  # continued from an earlier system has no label; it still selects. Cut
  # into runs of bars, only the run holding the label (or the end) gives
  # it its id.
  defp item(%TempoMark{} = mark, selection, range) do
    end_x = mark.line_to && mark.line_to + @tempo_end_gap

    [
      "<g",
      attr(
        "class",
        if(MapSet.member?(selection, mark.id), do: "tempo-mark selected", else: "tempo-mark")
      ),
      attr("data-tempo-id", mark.id),
      attr("font-family", "serif"),
      attr("font-size", @tempo_font_size),
      ">",
      tempo_label(mark, range),
      tempo_line(mark),
      tempo_end(mark, end_x, range),
      "</g>"
    ]
  end

  defp tempo_text(x, y, words, class, id) do
    [
      "<g",
      attr("id", id),
      attr("class", class),
      "><text",
      attr("x", n(x)),
      attr("y", n(y)),
      attr("font-family", "Bravura"),
      attr("font-size", @tempo_note_size),
      ">",
      Smufl.char(:metNoteQuarterUp),
      "</text><text",
      attr("x", n(x + @tempo_note_width)),
      attr("y", n(y)),
      attr("font-weight", "bold"),
      ">",
      escape(words),
      "</text></g>"
    ]
  end

  defp tempo_label(%TempoMark{start?: false}, _range), do: []

  defp tempo_label(%TempoMark{} = mark, range) do
    id = in_range?(mark.x, range) && "tempo-#{mark.id}"
    tempo_text(mark.x, mark.y, TempoMark.label(mark), "tempo-label", id)
  end

  defp tempo_end(%TempoMark{end?: false}, _end_x, _range), do: []

  defp tempo_end(%TempoMark{} = mark, end_x, range) do
    id = in_range?(end_x, range) && "tempo-end-#{mark.id}"
    tempo_text(end_x, mark.y, TempoMark.end_label(mark), "tempo-end", id)
  end

  defp tempo_line(%TempoMark{line_to: nil}), do: []

  defp tempo_line(%TempoMark{} = mark) do
    from = if mark.start?, do: mark.x + mark.width, else: mark.x

    [
      "<line",
      attr("x1", n(from)),
      attr("y1", n(mark.y - @tempo_line_rise)),
      attr("x2", n(mark.line_to)),
      attr("y2", n(mark.y - @tempo_line_rise)),
      attr("stroke", "currentColor"),
      attr("stroke-width", "0.12"),
      attr("stroke-dasharray", "0.6 0.5"),
      "/>"
    ]
  end

  defp in_range?(_x, :all), do: true
  defp in_range?(x, {x0, x1}), do: x >= x0 and x < x1

  defp dom_id(%Glyph{role: :notehead, id: id}), do: "note-#{id}"
  defp dom_id(%Glyph{role: :rest, id: id}) when is_binary(id), do: "rest-#{id}"
  defp dom_id(_glyph), do: nil

  defp beam_points(%Beam{x1: x1, y1: y1, x2: x2, y2: y2, thickness: t}) do
    [{x1, y1}, {x2, y2}, {x2, y2 + t}, {x1, y1 + t}]
    |> Enum.map(fn {x, y} -> [n(x), ",", n(y)] end)
    |> Enum.intersperse(" ")
  end

  # Two quadratic curves between the endpoints: the outer one bulges `dir`,
  # the inner one a little less, leaving the tie its midpoint thickness.
  defp tie_path(%Tie{x1: x1, x2: x2, y: y, dir: dir}) do
    sign = tie_sign(dir)

    height =
      (x2 - x1)
      |> Kernel.*(@tie_rise)
      |> max(@tie_min_height)
      |> min(@tie_max_height)

    inner = height - 2 * Smufl.default("tieMidpointThickness")
    mid = (x1 + x2) / 2

    [
      "M",
      join([x1, y], " "),
      " Q",
      join([mid, y + sign * height, x2, y], " "),
      " Q",
      join([mid, y + sign * inner, x1, y], " "),
      "Z"
    ]
  end

  defp tie_sign(:down), do: 1
  defp tie_sign(_up), do: -1

  # ` name="value"`; nothing for a nil or false value.
  defp attr(_name, value) when value in [nil, false], do: []
  defp attr(name, value), do: [" ", name, ~s(="), to_iodata(value), ~s(")]

  defp to_iodata(value) when is_binary(value) or is_list(value), do: value
  defp to_iodata(value) when is_atom(value), do: Atom.to_string(value)
  defp to_iodata(value) when is_number(value), do: n(value)

  defp escape(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp join(numbers, separator) do
    numbers
    |> Enum.map(&n/1)
    |> Enum.intersperse(separator)
  end

  defp n(x) when is_integer(x), do: Integer.to_string(x)
  defp n(x) when is_float(x), do: :erlang.float_to_binary(x, [{:decimals, @precision}, :compact])
end
