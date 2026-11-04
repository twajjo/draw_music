defmodule DrawMusic.Engraving.Layout do
  @moduledoc """
  Engraves a score: the position of everything drawn, in staff spaces with
  y pointing down.

  `layout/3` returns a `DrawMusic.Engraving.Engraved`: systems
  (`DrawMusic.Engraving.System`) stacked down the page, each with the
  geometry of its measures (`DrawMusic.Engraving.MeasureGeometry`) and the
  items drawn in it (`DrawMusic.Engraving.Item`), positioned relative to
  the system's treble top line.

  Options:

    * `width`: `:infinity` (the default) lays the whole piece out as one long
      system. A number wraps measures into systems of that width, each
      stretched to fill it, except a last system less than 60% full.
    * `spacing`: staff spaces per quarter note (default 8).
  """

  alias DrawMusic.Engraving.{
    Anchor,
    Beam,
    Brace,
    Column,
    Engraved,
    Glyph,
    Header,
    Item,
    Line,
    MeasureGeometry,
    Notes,
    Smufl,
    Staff,
    System,
    Tie
  }

  alias DrawMusic.Music.{Context, Duration, Measure, Score, Timeline}

  @spacing 8
  @min_stretch_fill 0.6

  # Horizontal gaps, in staff spaces.
  # Room before every note and rest: clicking there inserts ahead of it.
  @insert_gap 2.0
  # The least room after a column's notehead (for dots and flags).
  @min_note_space 2.5
  @right_pad 1.0
  @brace_gap 0.3
  @clef_pad 0.8
  @key_sign_gap 0.1
  @key_signature_pad 0.7
  @header_pad 1.0
  @tie_gap 0.1
  # A tie continued from the previous system starts this far before the
  # first note's measure content.
  @tie_lead_in 1.0

  # Vertical room, in staff spaces.
  @margin 2.0
  @clearance 1.0
  @system_gap 4.0
  @tie_offset 0.6
  @tie_extent 1

  # Time signature digits sit on the second and fourth staff lines.
  @numerator_line 1
  @denominator_line 3
  @digit_glyphs List.to_tuple(
                  ~w(timeSig0 timeSig1 timeSig2 timeSig3 timeSig4 timeSig5 timeSig6 timeSig7 timeSig8 timeSig9)a
                )

  @type option :: {:width, :infinity | number()} | {:spacing, number()}

  # A score with no measures (e.g. imported from an empty file) is drawn
  # as one empty bar.
  @spec layout(Score.t(), Context.t(), [option()]) :: Engraved.t()
  def layout(score, ctx, opts \\ [])

  def layout(%Score{measures: []} = score, ctx, opts) do
    layout(%{score | measures: [Measure.new()]}, ctx, opts)
  end

  def layout(%Score{} = score, %Context{} = ctx, opts) do
    width = Keyword.get(opts, :width, :infinity)
    scale = Keyword.get(opts, :spacing, @spacing) / Duration.ppq()
    last = length(score.measures) - 1
    tied_in = tied_in(score)

    # Each measure at its natural width; systems place and stretch them.
    measures =
      score.measures
      |> Enum.zip(Timeline.bars(score, ctx))
      |> Enum.with_index()
      |> Enum.map(fn {{measure, {start, capacity}}, index} ->
        {measure, natural_geometry(measure, index, start, capacity, scale)}
      end)

    {systems, anchors} =
      measures
      |> break(width, ctx)
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, fn {group, index}, anchors ->
        {system, system_anchors} = system(group, index, width, ctx, tied_in, last)
        located = Map.new(system_anchors, fn {id, anchor} -> {id, %{anchor | system: index}} end)
        {system, Map.merge(anchors, located)}
      end)

    {systems, height} =
      systems
      |> add_ties(score, anchors)
      |> stack()

    %Engraved{
      width: Enum.max_by(systems, & &1.width).width,
      height: height,
      systems: systems
    }
  end

  @doc "x of absolute tick `tick` in the measure laid out as `geom`."
  @spec x_of(MeasureGeometry.t(), number()) :: float()
  def x_of(%MeasureGeometry{} = geom, tick) do
    MeasureGeometry.x_at(geom, tick - geom.start_tick)
  end

  @doc "Absolute tick at `x` in the measure laid out as `geom` (not snapped to a grid)."
  @spec tick_at(MeasureGeometry.t(), number()) :: float()
  def tick_at(%MeasureGeometry{} = geom, x) do
    geom.start_tick + MeasureGeometry.offset_at(geom, x)
  end

  # A measure at its natural width, x from its left edge: a column for each
  # moment something starts (and beat 1), each one gap after the room the
  # previous one needs.
  defp natural_geometry(measure, index, start, capacity, scale) do
    starts =
      [{0, nil} | Enum.map(measure.notes ++ measure.rests, &{&1.offset, &1.staff})]
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {offset, staves} ->
        {offset, staves |> Enum.reject(&is_nil/1) |> Enum.uniq()}
      end)
      |> Enum.sort()

    room = fn ticks -> max(@min_note_space, ticks * scale) end
    nexts = Enum.map(tl(starts), &elem(&1, 0)) ++ [capacity]

    {columns, content_end} =
      starts
      |> Enum.zip(nexts)
      |> Enum.map_reduce(@insert_gap, fn {{offset, staves}, next}, x ->
        column = %Column{offset: offset, x: x, staves: Enum.sort(staves)}
        {column, x + room.(next - offset) + @insert_gap}
      end)

    content_end = content_end - @insert_gap

    %MeasureGeometry{
      index: index,
      x: 0.0,
      width: content_end + @right_pad,
      start_tick: start,
      capacity: capacity,
      content_x: @insert_gap,
      content_end: content_end,
      scale: scale,
      gap: @insert_gap,
      columns: columns
    }
  end

  ## Systems

  defp break(measures, :infinity, _ctx), do: [measures]

  defp break(measures, width, ctx) do
    measures
    |> Enum.reduce([], fn
      measure, [] ->
        [[measure]]

      {_m, geom} = measure, [current | _done] = systems ->
        used = header(ctx, length(systems) == 1).width + natural_width(current) + geom.width
        add_measure(systems, measure, used, width)
    end)
    |> Enum.reverse()
  end

  defp add_measure([current | done], measure, used, width) when used <= width do
    [current ++ [measure] | done]
  end

  defp add_measure(systems, measure, _used, _width), do: [[measure] | systems]

  defp natural_width(group), do: Enum.sum_by(group, fn {_m, geom} -> geom.width end)

  defp system(group, index, width, ctx, tied_in, last) do
    header = header(ctx, index == 0)
    natural = natural_width(group)
    {_m, last_geom} = List.last(group)
    factor = stretch(width, header.width, natural, last_geom.index == last)

    {placed, system_width} =
      Enum.map_reduce(group, header.width, fn {measure, natural_geom}, x ->
        place = &(x + &1 * factor)

        geom = %{
          natural_geom
          | x: x,
            width: natural_geom.width * factor,
            content_x: place.(natural_geom.content_x),
            content_end: place.(natural_geom.content_end),
            scale: natural_geom.scale * factor,
            gap: natural_geom.gap * factor,
            columns: Enum.map(natural_geom.columns, &%{&1 | x: place.(&1.x)})
        }

        {{measure, geom}, x + geom.width}
      end)

    {note_items, anchors} =
      Enum.reduce(placed, {[], %{}}, fn {measure, geom}, {items, anchors} ->
        tied = Map.get(tied_in, geom.index, MapSet.new())
        {more, more_anchors} = Notes.items(measure, geom.index, geom, ctx, tied)
        {items ++ more, Map.merge(anchors, more_anchors)}
      end)

    geoms = Enum.map(placed, &elem(&1, 1))

    items =
      header.items ++
        staff_lines(header.line_x, system_width) ++ barlines(geoms, last) ++ note_items

    {%System{index: index, width: system_width, measures: geoms, items: items}, anchors}
  end

  defp stretch(:infinity, _header, _natural, _last?), do: 1.0
  defp stretch(width, header, natural, last?), do: fill(natural, width - header, last?)

  defp fill(natural, available, true = _last?) when natural / available < @min_stretch_fill do
    1.0
  end

  defp fill(natural, available, _last?), do: available / natural

  ## Header: brace, clefs, key and time signatures

  defp header(ctx, first?) do
    line_x = brace_width() + @brace_gap
    clef_x = line_x + @clef_pad

    clefs = [
      glyph(:clef, :gClef, clef_x, Staff.y(:treble, Staff.clef_step(:treble))),
      glyph(:clef, :fClef, clef_x, Staff.y(:bass, Staff.clef_step(:bass)))
    ]

    key_x = clef_x + max(Smufl.width(:gClef), Smufl.width(:fClef)) + @clef_pad
    {key, key_end} = key_signature(ctx.sf, key_x)
    {time, time_end} = header_time(ctx, key_end, first?)

    %Header{
      items:
        [
          %Brace{x: 0, y1: 0, y2: Staff.bottom()},
          barline(line_x, Smufl.default("thinBarlineThickness"))
        ] ++ clefs ++ key ++ time,
      line_x: line_x,
      width: time_end + @header_pad
    }
  end

  # The brace glyph is one staff tall; it is stretched to span the grand staff.
  defp brace_width, do: Smufl.width(:brace) * Staff.bottom() / Staff.height()

  defp key_signature(0, x), do: {[], x}

  defp key_signature(sf, x) do
    glyph = key_glyph(sf)
    step = Smufl.width(glyph) + @key_sign_gap

    items =
      for staff <- [:treble, :bass],
          {position, i} <- Enum.with_index(Staff.key_signature_steps(staff, sf)) do
        glyph(:key, glyph, x + i * step, Staff.y(staff, position))
      end

    {items, x + abs(sf) * step + @key_signature_pad}
  end

  defp key_glyph(sf) when sf > 0, do: :accidentalSharp
  defp key_glyph(_sf), do: :accidentalFlat

  # Only the first system shows the time signature.
  defp header_time(ctx, x, true = _first?), do: time_signature(ctx, x)
  defp header_time(_ctx, x, false), do: {[], x}

  defp time_signature(%Context{time_symbol: :common}, x), do: time_symbol(:timeSigCommon, x)
  defp time_signature(%Context{time_symbol: :cut}, x), do: time_symbol(:timeSigCutCommon, x)

  defp time_signature(ctx, x) do
    numerator = digits(ctx.time_num)
    denominator = digits(ctx.time_den)
    width = max(digits_width(numerator), digits_width(denominator))

    items =
      for staff <- [:treble, :bass],
          {glyphs, line} <- [{numerator, @numerator_line}, {denominator, @denominator_line}],
          item <-
            digit_items(glyphs, x + (width - digits_width(glyphs)) / 2, Staff.top(staff) + line) do
        item
      end

    {items, x + width}
  end

  defp time_symbol(glyph, x) do
    items = for staff <- [:treble, :bass], do: glyph(:time, glyph, x, Staff.middle(staff))
    {items, x + Smufl.width(glyph)}
  end

  defp digits(n) do
    n
    |> Integer.digits()
    |> Enum.map(&elem(@digit_glyphs, &1))
  end

  defp digits_width(glyphs), do: Enum.sum_by(glyphs, &Smufl.width/1)

  defp digit_items(glyphs, x, y) do
    glyphs
    |> Enum.map_reduce(x, fn glyph, x -> {glyph(:time, glyph, x, y), x + Smufl.width(glyph)} end)
    |> elem(0)
  end

  ## Staff lines and bar lines

  defp staff_lines(x1, x2) do
    thickness = Smufl.default("staffLineThickness")

    for staff <- [:treble, :bass], line <- 0..Staff.height() do
      y = Staff.top(staff) + line
      %Line{role: :staff, x1: x1, y1: y, x2: x2, y2: y, thickness: thickness}
    end
  end

  # A thin bar line after each measure; a thin-thick final bar after the last.
  defp barlines(geoms, last), do: Enum.flat_map(geoms, &barline_items(&1, last))

  defp barline_items(%MeasureGeometry{index: last} = geom, last) do
    thin = Smufl.default("thinBarlineThickness")
    thick = Smufl.default("thickBarlineThickness")
    separation = Smufl.default("thinThickBarlineSeparation")
    right = geom.x + geom.width

    [
      barline(right - thick - separation - thin / 2, thin),
      barline(right - thick / 2, thick)
    ]
  end

  defp barline_items(geom, _last) do
    thin = Smufl.default("thinBarlineThickness")
    [barline(geom.x + geom.width - thin / 2, thin)]
  end

  defp barline(x, thickness) do
    %Line{role: :barline, x1: x, y1: 0, x2: x, y2: Staff.bottom(), thickness: thickness}
  end

  ## Ties

  # Measure index => ids of notes continuing a tie from the measure before.
  defp tied_in(score) do
    indexed = Enum.with_index(score.measures)
    measure_of = for {m, i} <- indexed, n <- m.notes, into: %{}, do: {n.id, i}

    for {m, i} <- indexed, n <- m.notes, n.tie_to, measure_of[n.tie_to] == i + 1, reduce: %{} do
      acc -> Map.update(acc, i + 1, MapSet.new([n.tie_to]), &MapSet.put(&1, n.tie_to))
    end
  end

  defp add_ties(systems, score, anchors) do
    by_system =
      for m <- score.measures,
          n <- m.notes,
          from = n.tie_to && anchors[n.id],
          to = from && anchors[n.tie_to],
          to,
          tie <- tie_items(from, to, systems) do
        tie
      end

    by_system = Enum.group_by(by_system, &elem(&1, 0), &elem(&1, 1))
    Enum.map(systems, fn s -> %{s | items: s.items ++ Map.get(by_system, s.index, [])} end)
  end

  # Ties curve away from the stem. One crossing a system break is drawn as
  # two halves: to the end of the first system, and from the start of the
  # next system's first measure.
  defp tie_items(%Anchor{system: system} = from, %Anchor{system: system} = to, _systems) do
    dir = away_from(from.dir)
    [{system, tie(from.x1 + @tie_gap, to.x0 - @tie_gap, from.y, dir)}]
  end

  defp tie_items(%Anchor{} = from, %Anchor{} = to, systems) do
    dir = away_from(from.dir)
    source = Enum.at(systems, from.system)
    target = Enum.at(systems, to.system)
    continued_x = hd(target.measures).content_x - @tie_lead_in

    [
      {from.system, tie(from.x1 + @tie_gap, source.width, from.y, dir)},
      {to.system, tie(continued_x, to.x0 - @tie_gap, to.y, dir)}
    ]
  end

  defp away_from(:up), do: :down
  defp away_from(_stem_dir), do: :up

  defp tie(x1, x2, note_y, :down), do: %Tie{x1: x1, x2: x2, y: note_y + @tie_offset, dir: :down}
  defp tie(x1, x2, note_y, :up), do: %Tie{x1: x1, x2: x2, y: note_y - @tie_offset, dir: :up}

  ## Vertical stacking

  # Each system gets room above and below for whatever sticks out of the
  # grand staff.
  defp stack(systems) do
    {systems, bottom} =
      Enum.map_reduce(systems, 0.0, fn system, y ->
        {top, bottom} =
          system.items
          |> Enum.flat_map(&y_range/1)
          |> Enum.min_max()

        above = max(@margin, -top + @clearance)
        below = max(@margin, bottom - Staff.bottom() + @clearance)
        system_y = y + above
        {%{system | y: system_y}, system_y + Staff.bottom() + below + @system_gap}
      end)

    {systems, bottom - @system_gap}
  end

  @spec y_range(Item.t()) :: [number()]
  defp y_range(%Glyph{glyph: glyph, y: y}) do
    {_x0, y0, _x1, y1} = Smufl.bbox(glyph)
    [y - y1, y - y0]
  end

  defp y_range(%Line{y1: y1, y2: y2}), do: [y1, y2]
  defp y_range(%Beam{} = b), do: [b.y1, b.y2, b.y1 + b.thickness, b.y2 + b.thickness]
  defp y_range(%Tie{y: y}), do: [y - @tie_extent, y + @tie_extent]
  defp y_range(%Brace{y1: y1, y2: y2}), do: [y1, y2]

  defp glyph(role, glyph, x, y), do: %Glyph{role: role, glyph: glyph, x: x, y: y}
end
