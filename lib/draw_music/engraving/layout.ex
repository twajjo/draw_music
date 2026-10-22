defmodule DrawMusic.Engraving.Layout do
  @moduledoc """
  Engraves a score: the position of everything drawn, in staff spaces with
  y pointing down.

  `layout/3` returns `%{width, height, systems}`. Each system has:

    * `index` and `y`, where its treble staff's top line sits on the page;
    * `width`;
    * `measures`: the geometry that maps between ticks and x, as
      `%{index, x, width, start_tick, capacity, content_x, scale}`. Tick
      `t` of the measure lies at `content_x + (t - start_tick) * scale`;
    * `items`, positioned relative to the system's treble top line:
      * `%{type: :glyph, role, glyph, x, y}`. `role` is `:clef`, `:key`,
        `:time`, `:notehead` (with `id`), `:accidental`, `:dot`, `:flag` or
        `:rest` (with `id`, nil for a whole-bar rest on an empty staff);
      * `%{type: :line, role, x1, y1, x2, y2, thickness}`. `role` is
        `:staff`, `:ledger`, `:stem` (with `dir`) or `:barline`;
      * `%{type: :beam, x1, y1, x2, y2, thickness}`: a beam whose edge runs
        along the line, extending by `thickness` (positive is downwards);
      * `%{type: :tie, x1, x2, y, dir}`: an arc bulging `dir` (`:up` or `:down`);
      * `%{type: :brace, x, y1, y2}`.

  Options:

    * `width`: `:infinity` (the default) lays the whole piece out as one long
      system. A number wraps measures into systems of that width, each
      stretched to fill it, except a last system less than 60% full.
    * `spacing`: staff spaces per quarter note (default 8).
  """

  alias DrawMusic.Engraving.{Notes, Smufl, Staff}
  alias DrawMusic.Music.{Context, Duration, Score, Timeline}

  @spacing 8
  @left_pad 2.0
  @right_pad 1.0
  @margin 2.0
  @system_gap 4.0
  @min_stretch_fill 0.6
  @tie_gap 0.1
  @tie_offset 0.6

  @digit_glyphs ~w(timeSig0 timeSig1 timeSig2 timeSig3 timeSig4 timeSig5 timeSig6 timeSig7 timeSig8 timeSig9)a

  def layout(%Score{} = score, %Context{} = ctx, opts \\ []) do
    width = Keyword.get(opts, :width, :infinity)
    scale = Keyword.get(opts, :spacing, @spacing) / Duration.ppq()
    last = length(score.measures) - 1
    tied_in = tied_in(score)

    measures =
      score.measures
      |> Enum.zip(Timeline.bars(score, ctx))
      |> Enum.with_index()
      |> Enum.map(fn {{measure, {start, capacity}}, index} ->
        %{
          measure: measure,
          index: index,
          start_tick: start,
          capacity: capacity,
          scale: scale,
          width: @left_pad + capacity * scale + @right_pad
        }
      end)

    {systems, anchors} =
      measures
      |> break(width, ctx)
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, fn {group, index}, anchors ->
        {system, system_anchors} = system(group, index, width, ctx, tied_in, last)

        {system,
         Map.merge(
           anchors,
           Map.new(system_anchors, fn {id, a} -> {id, Map.put(a, :system, index)} end)
         )}
      end)

    {systems, height} = systems |> add_ties(score, anchors) |> stack()
    %{width: systems |> Enum.map(& &1.width) |> Enum.max(), height: height, systems: systems}
  end

  @doc "x of absolute tick `tick` in the measure laid out as `geom`."
  def x_of(geom, tick), do: geom.content_x + (tick - geom.start_tick) * geom.scale

  @doc "Absolute tick at `x` in the measure laid out as `geom` (not snapped to a grid)."
  def tick_at(geom, x), do: geom.start_tick + (x - geom.content_x) / geom.scale

  ## Systems

  defp break(measures, :infinity, _ctx), do: [measures]

  defp break(measures, width, ctx) do
    measures
    |> Enum.reduce([], fn
      measure, [] ->
        [[measure]]

      measure, [current | done] = systems ->
        used =
          header(ctx, length(systems) == 1).width + Enum.sum_by(current, & &1.width) +
            measure.width

        if used <= width, do: [current ++ [measure] | done], else: [[measure] | systems]
    end)
    |> Enum.reverse()
  end

  defp system(group, index, width, ctx, tied_in, last) do
    header = header(ctx, index == 0)
    natural = Enum.sum_by(group, & &1.width)
    factor = stretch(width, header.width, natural, List.last(group).index == last)

    {placed, system_width} =
      Enum.map_reduce(group, header.width, fn m, x ->
        geom = %{
          index: m.index,
          x: x,
          width: m.width * factor,
          start_tick: m.start_tick,
          capacity: m.capacity,
          content_x: x + @left_pad * factor,
          scale: m.scale * factor
        }

        {{m.measure, geom}, x + geom.width}
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

    {%{index: index, width: system_width, measures: geoms, items: items}, anchors}
  end

  defp stretch(:infinity, _header, _natural, _last?), do: 1.0

  defp stretch(width, header, natural, last?) do
    available = width - header
    if last? and natural / available < @min_stretch_fill, do: 1.0, else: available / natural
  end

  ## Header: brace, clefs, key and time signatures

  defp header(ctx, first?) do
    bottom = Staff.bottom()
    line_x = brace_width() + 0.3
    clef_x = line_x + 0.8

    clefs = [
      glyph(:clef, :gClef, clef_x, Staff.y(:treble, 32)),
      glyph(:clef, :fClef, clef_x, Staff.y(:bass, 24))
    ]

    key_x = clef_x + max(Smufl.width(:gClef), Smufl.width(:fClef)) + 0.8
    {key, key_end} = key_signature(ctx.sf, key_x)
    {time, time_end} = if first?, do: time_signature(ctx, key_end), else: {[], key_end}

    %{
      items:
        [
          %{type: :brace, x: 0, y1: 0, y2: bottom},
          barline(line_x, Smufl.default("thinBarlineThickness"))
        ] ++
          clefs ++ key ++ time,
      line_x: line_x,
      width: time_end + 1.0
    }
  end

  # The brace glyph is one staff (4 spaces) tall; it is stretched to span
  # the grand staff.
  defp brace_width, do: Smufl.width(:brace) * Staff.bottom() / 4

  defp key_signature(0, x), do: {[], x}

  defp key_signature(sf, x) do
    glyph = if sf > 0, do: :accidentalSharp, else: :accidentalFlat
    step = Smufl.width(glyph) + 0.1

    items =
      for staff <- [:treble, :bass],
          {position, i} <- Enum.with_index(Staff.key_signature_steps(staff, sf)),
          do: glyph(:key, glyph, x + i * step, Staff.y(staff, position))

    {items, x + abs(sf) * step + 0.7}
  end

  defp time_signature(%Context{time_symbol: symbol}, x) when symbol in [:common, :cut] do
    glyph = if symbol == :common, do: :timeSigCommon, else: :timeSigCutCommon
    items = for staff <- [:treble, :bass], do: glyph(:time, glyph, x, Staff.middle(staff))
    {items, x + Smufl.width(glyph)}
  end

  defp time_signature(ctx, x) do
    numerator = digits(ctx.time_num)
    denominator = digits(ctx.time_den)
    width = max(digits_width(numerator), digits_width(denominator))

    items =
      for staff <- [:treble, :bass],
          {glyphs, y} <- [{numerator, Staff.top(staff) + 1}, {denominator, Staff.top(staff) + 3}],
          item <- digit_items(glyphs, x + (width - digits_width(glyphs)) / 2, y),
          do: item

    {items, x + width}
  end

  defp digits(n), do: n |> Integer.digits() |> Enum.map(&Enum.at(@digit_glyphs, &1))
  defp digits_width(glyphs), do: Enum.sum_by(glyphs, &Smufl.width/1)

  defp digit_items(glyphs, x, y) do
    glyphs
    |> Enum.map_reduce(x, fn glyph, x -> {glyph(:time, glyph, x, y), x + Smufl.width(glyph)} end)
    |> elem(0)
  end

  ## Staff lines and bar lines

  defp staff_lines(x1, x2) do
    thickness = Smufl.default("staffLineThickness")

    for staff <- [:treble, :bass], line <- 0..4 do
      y = Staff.top(staff) + line
      %{type: :line, role: :staff, x1: x1, y1: y, x2: x2, y2: y, thickness: thickness}
    end
  end

  # A thin bar line after each measure; a thin-thick final bar after the last.
  defp barlines(geoms, last) do
    thin = Smufl.default("thinBarlineThickness")
    thick = Smufl.default("thickBarlineThickness")
    separation = Smufl.default("thinThickBarlineSeparation")

    Enum.flat_map(geoms, fn geom ->
      right = geom.x + geom.width

      if geom.index == last,
        do: [
          barline(right - thick - separation - thin / 2, thin),
          barline(right - thick / 2, thick)
        ],
        else: [barline(right - thin / 2, thin)]
    end)
  end

  defp barline(x, thickness),
    do: %{
      type: :line,
      role: :barline,
      x1: x,
      y1: 0,
      x2: x,
      y2: Staff.bottom(),
      thickness: thickness
    }

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
          tie <- tie_items(from, to, systems),
          do: tie

    by_system = Enum.group_by(by_system, &elem(&1, 0), &elem(&1, 1))
    Enum.map(systems, fn s -> %{s | items: s.items ++ Map.get(by_system, s.index, [])} end)
  end

  # Ties curve away from the stem. One crossing a system break is drawn as
  # two halves: to the end of the first system, and from the start of the
  # next system's first measure.
  defp tie_items(from, to, systems) do
    dir = if from.dir == :up, do: :down, else: :up
    dy = if dir == :down, do: @tie_offset, else: -@tie_offset

    if from.system == to.system do
      [{from.system, tie(from.x1 + @tie_gap, to.x0 - @tie_gap, from.y + dy, dir)}]
    else
      source = Enum.at(systems, from.system)
      target = Enum.at(systems, to.system)

      [
        {from.system, tie(from.x1 + @tie_gap, source.width, from.y + dy, dir)},
        {to.system, tie(hd(target.measures).content_x - 1.0, to.x0 - @tie_gap, to.y + dy, dir)}
      ]
    end
  end

  defp tie(x1, x2, y, dir), do: %{type: :tie, x1: x1, x2: x2, y: y, dir: dir}

  ## Vertical stacking

  # Each system gets room above and below for whatever sticks out of the
  # grand staff.
  defp stack(systems) do
    {systems, bottom} =
      Enum.map_reduce(systems, 0.0, fn system, y ->
        {top, bottom} = system.items |> Enum.flat_map(&y_range/1) |> Enum.min_max()
        above = max(@margin, -top + 1.0)
        below = max(@margin, bottom - Staff.bottom() + 1.0)
        system_y = y + above
        {Map.put(system, :y, system_y), system_y + Staff.bottom() + below + @system_gap}
      end)

    {systems, bottom - @system_gap}
  end

  defp y_range(%{type: :glyph, glyph: glyph, y: y}) do
    {_x0, y0, _x1, y1} = Smufl.bbox(glyph)
    [y - y1, y - y0]
  end

  defp y_range(%{type: :line, y1: y1, y2: y2}), do: [y1, y2]
  defp y_range(%{type: :beam} = b), do: [b.y1, b.y2, b.y1 + b.thickness, b.y2 + b.thickness]
  defp y_range(%{type: :tie, y: y}), do: [y - 1, y + 1]
  defp y_range(%{type: :brace, y1: y1, y2: y2}), do: [y1, y2]

  defp glyph(role, glyph, x, y), do: %{type: :glyph, role: role, glyph: glyph, x: x, y: y}
end
